#!/usr/bin/env bash
set -euo pipefail

# Build Yoga (C++) static library into src/ffi/yoga-install/lib/libyogacore.a
# Executed with CWD = onebit-yoga/src/ffi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # points to src/ffi
INSTALL_DIR="$ROOT_DIR/yoga-install"
VENDOR_DIR_PRIMARY="$ROOT_DIR/vendor/yoga"
VENDOR_DIR_FALLBACK="$(cd "$ROOT_DIR/../../build/yoga" 2>/dev/null && pwd || true)"

if ! command -v cmake >/dev/null 2>&1; then
  echo "[onebit-yoga] 'cmake' not found. Skipping native build (docs/CI safe)." >&2
  exit 0
fi

if ! command -v make >/dev/null 2>&1; then
  echo "[onebit-yoga] 'make' not found. Skipping native build (docs/CI safe)." >&2
  exit 0
fi

SRC_BASE=""
if [ -d "$VENDOR_DIR_PRIMARY" ]; then
  if [ -f "$VENDOR_DIR_PRIMARY/CMakeLists.txt" ]; then
    SRC_BASE="$VENDOR_DIR_PRIMARY"
  elif [ -f "$VENDOR_DIR_PRIMARY/yoga/CMakeLists.txt" ]; then
    SRC_BASE="$VENDOR_DIR_PRIMARY/yoga"
  else
    SRC_BASE="$VENDOR_DIR_PRIMARY"
  fi
elif [ -n "$VENDOR_DIR_FALLBACK" ] && [ -d "$VENDOR_DIR_FALLBACK" ]; then
  if [ -f "$VENDOR_DIR_FALLBACK/CMakeLists.txt" ]; then
    SRC_BASE="$VENDOR_DIR_FALLBACK"
  elif [ -f "$VENDOR_DIR_FALLBACK/yoga/CMakeLists.txt" ]; then
    SRC_BASE="$VENDOR_DIR_FALLBACK/yoga"
  else
    SRC_BASE="$VENDOR_DIR_FALLBACK"
  fi
else
  echo "[onebit-yoga] Yoga sources not found. Skipping native build (docs/CI safe)." >&2
  exit 0
fi

# Start with the detected base directory; may be patched below
SRC_DIR="$SRC_BASE"

echo "[onebit-yoga] Building Yoga from: $SRC_DIR"

BUILD_DIR="$SRC_DIR/build"
mkdir -p "$BUILD_DIR"

# If no CMakeLists at SRC_DIR, synthesize a minimal one pointing at yoga/ sources
if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
  echo "[onebit-yoga] No CMakeLists in $SRC_DIR; generating minimal CMake project …"
  TMP_MIN="$ROOT_DIR/vendor/yoga.minbuild"
  rm -rf "$TMP_MIN"
  mkdir -p "$TMP_MIN"
  cat > "$TMP_MIN/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(yogacore C CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
file(GLOB_RECURSE YOGA_SOURCES "yoga/*.cpp")
add_library(yogacore STATIC ${YOGA_SOURCES})
target_include_directories(yogacore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
install(TARGETS yogacore ARCHIVE DESTINATION lib)
install(DIRECTORY yoga/ DESTINATION include/yoga FILES_MATCHING PATTERN "*.h")
EOF
  mkdir -p "$TMP_MIN/yoga"
  cp -R "$SRC_BASE/yoga/" "$TMP_MIN/yoga/" 2>/dev/null || true
  SRC_DIR="$TMP_MIN"
  BUILD_DIR="$SRC_DIR/build"
  mkdir -p "$BUILD_DIR"
fi

# If building from trimmed vendor, patch out tests subdir which is pruned
if [ ! -d "$SRC_DIR/tests" ] && [ -f "$SRC_DIR/CMakeLists.txt" ]; then
  if grep -q "add_subdirectory( *tests *)" "$SRC_DIR/CMakeLists.txt"; then
    echo "Creating patched build source (skip tests) …"
    TMP_SRC="$ROOT_DIR/vendor/yoga.buildsrc"
    rm -rf "$TMP_SRC"
    mkdir -p "$TMP_SRC"
    cp -R "$SRC_DIR/" "$TMP_SRC/"
    # Remove any pre-existing build cache from copied source
    rm -rf "$TMP_SRC/build"
    sed -i.bak 's/^\(.*add_subdirectory( *tests *).*\)$/# \1 (pruned)/' "$TMP_SRC/CMakeLists.txt" || true
    rm -f "$TMP_SRC/CMakeLists.txt.bak" || true
    SRC_DIR="$TMP_SRC"
    BUILD_DIR="$SRC_DIR/build"
    mkdir -p "$BUILD_DIR"
  fi
fi

cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DYOGA_BUILD_TESTS=OFF \
  -DYOGA_BUILD_BENCHMARKS=OFF

# parallel build
if command -v nproc >/dev/null 2>&1; then
  cmake --build "$BUILD_DIR" --config Release -j"$(nproc)"
elif command -v sysctl >/dev/null 2>&1; then
  cmake --build "$BUILD_DIR" --config Release -j"$(sysctl -n hw.ncpu)"
else
  cmake --build "$BUILD_DIR" --config Release -j
fi
cmake --install "$BUILD_DIR"

if [ ! -f "$INSTALL_DIR/lib/libyogacore.a" ]; then
  echo "Error: libyogacore.a not found in $INSTALL_DIR/lib" >&2
  exit 1
fi

echo "✓ Yoga static library ready: yoga-install/lib/libyogacore.a"

# Prune test artifacts to keep .mooncakes minimal
rm -f "$INSTALL_DIR/lib/libgtest"*.a || true
rm -f "$INSTALL_DIR/lib/libgmock"*.a || true
rm -rf "$INSTALL_DIR/lib/pkgconfig" || true
rm -rf "$INSTALL_DIR/lib/cmake/GTest" || true
rm -rf "$INSTALL_DIR/include/gtest" "$INSTALL_DIR/include/gmock" || true

# Clean patched build source if created
if [ -n "${TMP_SRC:-}" ] && [ -d "$TMP_SRC" ]; then
  rm -rf "$TMP_SRC"
fi

# Build C wrapper into a static library for Moon linking
echo "[onebit-yoga] Building Yoga FFI wrapper (libyoga_wrap.a) …"
cc -c -o "$ROOT_DIR/yoga_wrap.o" -I "$INSTALL_DIR/include" -fPIC "$ROOT_DIR/yoga_wrap.c"
ar rcs "$ROOT_DIR/libyoga_wrap.a" "$ROOT_DIR/yoga_wrap.o"
echo "✓ Wrapper static library ready: src/ffi/libyoga_wrap.a"

exit 0
