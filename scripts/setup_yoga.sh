#!/bin/bash
# ============================================================================
# setup_yoga.sh — Fix the onebit-yoga "no-op stub" bug for native builds.
#
# WHY THIS EXISTS
# ---------------
# The `Frank-III/onebit-yoga` package (transitive dep of onebit-tui) ships a
# FAKE layout engine in `src/ffi/yoga_stubs.c`. Its `YGNodeCalculateLayout`
# does NOTHING — it never positions children, so every TUI node collapses to
# top=0/left=0 and the whole terminal UI renders on top of itself.
#
# The REAL Yoga C++ engine is vendored in the package but never linked. This
# script builds the real engine into a static lib and rewires the build to
# use it instead of the stub.
#
# Run this once after `moon install` (or whenever `.mooncakes` is regenerated),
# then `moon build` / `moon test` will have working layout.
# ============================================================================
set -e

REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
VENDOR="$REPO/vendor/yoga"
YOGA_SRC="$VENDOR/src"          # vendored Yoga C++ (yoga/*.cpp)
WRAP="$VENDOR/yoga_wrap.c"      # C wrapper bridging MoonBit FFI to Yoga
OUT="$VENDOR/lib"
OBJ="$VENDOR/obj"

# The onebit-yoga ffi package in the mooncakes cache.
FFI_PKG="$REPO/.mooncakes/Frank-III/onebit-yoga/src/ffi"

command -v g++ >/dev/null || { echo "ERROR: g++ not found. Install: apt-get install -y g++"; exit 1; }

echo "[1/3] Building real Yoga static lib from vendored sources..."
mkdir -p "$OUT" "$OBJ"
OBJS=""
i=0
while IFS= read -r f; do
  o="$OBJ/y_$i.o"
  g++ -std=c++20 -O2 -fPIC -I"$YOGA_SRC" -c "$f" -o "$o"
  OBJS="$OBJS $o"
  i=$((i+1))
done < <(find "$YOGA_SRC/yoga" -name "*.cpp")
gcc -O2 -fPIC -I"$YOGA_SRC" -c "$WRAP" -o "$OBJ/wrap.o"
ar rcs "$OUT/libyoga_full.a" $OBJS "$OBJ/wrap.o"
echo "      -> $OUT/libyoga_full.a ($i C++ sources + wrapper)"

echo "[2/3] Disabling the fake stub in the mooncakes cache..."
if [ -d "$FFI_PKG" ]; then
  cat > "$FFI_PKG/moon.pkg.json" <<'JSON'
{
  "import": ["Frank-III/onebit-yoga/types"],
  "warn-list": "-1-3-4-6-9-19-35",
  "pre-build": [],
  "native-stub": [],
  "link": false
}
JSON
  echo "      -> patched $FFI_PKG/moon.pkg.json (native-stub emptied)"
else
  echo "      -> WARNING: $FFI_PKG not found (run 'moon install' first?)"
fi

echo "[3/3] Done. The real Yoga engine is now linked via cmd/moon.pkg and"
echo "      lib/tui/moon.pkg (cc-link-flags -> $OUT/libyoga_full.a)."
