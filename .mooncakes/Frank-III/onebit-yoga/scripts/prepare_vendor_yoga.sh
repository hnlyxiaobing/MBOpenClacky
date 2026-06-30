#!/usr/bin/env bash
set -euo pipefail

# Prepare a trimmed Yoga vendor tree for publishing.
# Copies only what's required to build static libyogacore.a:
#  - CMakeLists.txt
#  - cmake/ (modules)
#  - yoga/ (C++ sources)
#  - LICENSE
# Excludes tests, benchmarks, language bindings, docs, etc.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_ROOT="$ROOT_DIR/build/yoga"
DEST_ROOT="$ROOT_DIR/src/ffi/vendor/yoga"

if [ ! -d "$SRC_ROOT" ]; then
  echo "Error: $SRC_ROOT not found. Ensure build/yoga exists (submodule/clone)." >&2
  exit 1
fi

echo "Preparing trimmed Yoga vendor from: $SRC_ROOT"
rm -rf "$DEST_ROOT"
mkdir -p "$DEST_ROOT"

cp -f "$SRC_ROOT/CMakeLists.txt" "$DEST_ROOT/"
[ -d "$SRC_ROOT/cmake" ] && cp -R "$SRC_ROOT/cmake" "$DEST_ROOT/cmake"
cp -R "$SRC_ROOT/yoga" "$DEST_ROOT/yoga"
[ -f "$SRC_ROOT/LICENSE" ] && cp -f "$SRC_ROOT/LICENSE" "$DEST_ROOT/"

echo "✓ Trimmed Yoga vendor prepared at: $DEST_ROOT"

