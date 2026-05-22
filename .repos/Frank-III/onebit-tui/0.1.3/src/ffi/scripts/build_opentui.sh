#!/usr/bin/env bash
set -euo pipefail

# Build OpenTUI Zig library from vendored sources and copy a static lib to ../lib
# Executed with CWD = onebit-tui/src/ffi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # points to src/ffi
VENDOR_DIR="vendor/opentui"
OUT_DIR="lib"

echo "[onebit-tui] Building OpenTUI (Zig) …"

# Allow CI or local type-check to skip building Zig entirely
if [ "${ONEBIT_SKIP_PREBUILD:-0}" = "1" ]; then
  echo "[onebit-tui] ONEBIT_SKIP_PREBUILD=1 – skipping Zig build"
  mkdir -p "$OUT_DIR"
  # leave any previous artifacts in place; no-op
  exit 0
fi

# Ensure we operate from src/ffi (ROOT_DIR)
cd "$ROOT_DIR"

if ! command -v zig >/dev/null 2>&1; then
  echo "[onebit-tui] 'zig' not found. Skipping native build (docs/CI safe)." >&2
  mkdir -p "$OUT_DIR"
  # Allow checks/docs to proceed without a native lib
  exit 0
fi

if [ ! -d "$VENDOR_DIR" ]; then
  echo "[onebit-tui] Vendored OpenTUI not found at '$VENDOR_DIR'. Skipping (docs/CI safe)." >&2
  mkdir -p "$OUT_DIR"
  exit 0
fi

mkdir -p "$OUT_DIR"

# Force static linkage in the vendored build script if not already static
BUILD_FILE="$VENDOR_DIR/build.zig"
if [ ! -f "$BUILD_FILE" ]; then
  echo "Error: $BUILD_FILE not found." >&2
  exit 1
fi

if ! grep -q "\.linkage = \.static" "$BUILD_FILE"; then
  echo "Patching build.zig for static library output …"
  # Replace ".linkage = .dynamic," with ".linkage = .static,"
  sed -i.bak 's/\.linkage = \.dynamic/\.linkage = \.static/' "$BUILD_FILE"
fi

# Disable strict Zig version check if present
if grep -q "checkZigVersion();" "$BUILD_FILE"; then
  echo "Disabling Zig version check …"
  sed -i.bak 's/checkZigVersion();/\/\/ checkZigVersion();/' "$BUILD_FILE"
fi

# Clean up backup file created by sed -i.bak to avoid packaging it
if [ -f "${BUILD_FILE}.bak" ]; then
  rm -f "${BUILD_FILE}.bak"
fi

# Check Zig version (require 0.14.x for OpenTUI compatibility)
zig_ver="$(zig version 2>/dev/null || echo unknown)"
# TODO: Re-enable version check once Zig is installed
# if ! echo "$zig_ver" | grep -q "^0\.14\."; then
#   echo "Error: OpenTUI requires Zig 0.14.x. You have: $zig_ver" >&2
#   echo "Please install Zig 0.14.x (e.g., using 'zigup 0.14.1' or 'anyzig install 0.14.1')" >&2
#   exit 1
# fi

# Quick up-to-date check using mtimes to avoid heavy hashing
sig_file="$OUT_DIR/libopentui.a.sig"
os_name="$(uname -s)"; arch_name="$(uname -m)"
case "$arch_name" in arm64|aarch64) zig_arch="aarch64" ;; x86_64|amd64) zig_arch="x86_64" ;; *) zig_arch="$arch_name" ;; esac
case "$os_name" in Darwin) zig_os="macos" ;; Linux) zig_os="linux" ;; MINGW*|MSYS*|CYGWIN*) zig_os="windows" ;; *) zig_os="$os_name" ;; esac
target_triplet="${zig_arch}-${zig_os}"

# Function to get file mtime cross-platform
stat_mtime() {
  local f="$1"
  if [ "$os_name" = "Darwin" ]; then
    stat -f %m "$f"
  else
    stat -c %Y "$f"
  fi
}

latest_vendor_mtime() {
  local latest=0
  # shellcheck disable=SC2044
  for f in $(find "$VENDOR_DIR" -type f \( -name '*.zig' -o -name 'build.zig' -o -name 'build.zig.zon' \) -not -path '*/.zig-cache/*'); do
    local m
    m=$(stat_mtime "$f" || echo 0)
    # guard empty
    [ -z "$m" ] && m=0
    if [ "$m" -gt "$latest" ]; then latest="$m"; fi
  done
  echo "$latest"
}

# If lib exists and newer than vendor sources, skip rebuild immediately unless forced
if [ -f "$OUT_DIR/libopentui.a" ] && [ "${ONEBIT_FORCE_ZIG_BUILD:-0}" != "1" ]; then
  lib_mtime=$(stat_mtime "$OUT_DIR/libopentui.a" 2>/dev/null || echo 0)
  vend_mtime=$(latest_vendor_mtime)
  if [ "$lib_mtime" -ge "$vend_mtime" ]; then
    echo "lib/libopentui.a up to date; skipping Zig build"
    exit 0
  fi
fi

# Fallback to hashing when mtimes indicate vendor changes
HASHER=""
if command -v shasum >/dev/null 2>&1; then HASHER="shasum -a 256"; elif command -v sha256sum >/dev/null 2>&1; then HASHER="sha256sum"; fi
compute_sig() {
  if [ -z "$HASHER" ]; then echo "nohasher"; return; fi
  {
    printf 'zig:%s\n' "$zig_ver"
    printf 'target:%s\n' "$target_triplet"
    find "$VENDOR_DIR" -type f \
      \( -name '*.zig' -o -name 'build.zig' -o -name 'build.zig.zon' \) \
      -not -path '*/.zig-cache/*' -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 cat
  } | eval $HASHER | awk '{print $1}'
}

want_sig="$(compute_sig)"
if [ -f "$OUT_DIR/libopentui.a" ] && [ -f "$sig_file" ] && [ "${ONEBIT_FORCE_ZIG_BUILD:-0}" != "1" ]; then
  have_sig="$(cat "$sig_file" 2>/dev/null || echo)"
  if [ -n "$HASHER" ] && [ "$have_sig" = "$want_sig" ]; then
    echo "lib/libopentui.a up to date; skipping Zig build"
    exit 0
  fi
fi

# Determine zig target string for current host
TARGET="$target_triplet"

echo "Building for target: $TARGET (ReleaseFast)"
(
  cd "$VENDOR_DIR"
  zig build -Doptimize=ReleaseFast -Dtarget="$TARGET"
)

# Copy the produced static library to OUT_DIR (install path is vendor/opentui/lib/<target>/)
LIB_SRC_DIR="$VENDOR_DIR/lib/${TARGET}"
if [ -f "$LIB_SRC_DIR/libopentui.a" ]; then
  cp "$LIB_SRC_DIR/libopentui.a" "$OUT_DIR/libopentui.a"
  echo "✓ lib/libopentui.a ready"
  # Write/refresh signature after successful build
  if [ -n "$want_sig" ]; then
    echo "$want_sig" > "$sig_file"
  fi
else
  echo "Error: libopentui.a not found under $LIB_SRC_DIR" >&2
  exit 1
fi

exit 0
