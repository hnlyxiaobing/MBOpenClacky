#!/usr/bin/env bash
# Apply MoonBit-toolchain compatibility patches to the upstream
# bobzhang/crescent@0.10.0 dependency after a fresh `moon install` or
# `moon build` fetches it from the registry.
#
# The upstream crescent@0.10.0 was written for an older MoonBit toolchain.
# Breaking changes in the current toolchain include:
#   - Struct constructors now use named syntax: `Foo::foo(...)` not `Foo(...)`
#   - `Map::new()` replaced by `Map([])`
#   - `inspect` replaced by `@debug.debug_inspect`
#   - `derive(Debug)` required by `assert_eq` in test blocks
#
# This script is idempotent — it skips the patch if already applied.
#
# Usage: bash scripts/patch_crescent.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$PROJECT_ROOT/.mooncakes/bobzhang/crescent"
PATCH_FILE="$SCRIPT_DIR/crescent_compat.patch"

if [ ! -d "$TARGET_DIR" ]; then
  echo "crescent directory not found at $TARGET_DIR — skipping patch."
  exit 0
fi

# Check if already patched by looking for the named constructor in request.mbt
if grep -q 'pub fn HttpRequest::http_request' "$TARGET_DIR/core/request.mbt" 2>/dev/null; then
  echo "crescent patches already applied — skipping."
  exit 0
fi

echo "Applying crescent compatibility patches..."
(cd "$TARGET_DIR" && patch -p1 --forward --silent < "$PATCH_FILE")
echo "crescent patches applied successfully."
