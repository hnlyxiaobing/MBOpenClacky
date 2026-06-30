#!/usr/bin/env bash
set -euo pipefail

# Populate vendored sources under src/ffi/vendor based on scripts/vendor.lock

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/scripts/vendor.lock"
VENDOR_BASE="$ROOT_DIR/src/ffi/vendor"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required to parse vendor.lock" >&2
  exit 1
fi

mkdir -p "$VENDOR_BASE"

fetch_repo() {
  local name="$1"
  local dest="$2"
  local repo ref
  repo=$(python3 - <<PY
import json,sys
data=json.load(open('$LOCK_FILE'))
print(data['$1']['repo'])
PY
)
  ref=$(python3 - <<PY
import json,sys
data=json.load(open('$LOCK_FILE'))
print(data['$1']['ref'])
PY
)
  if [ -d "$dest/.git" ]; then
    echo "[$name] Already present at $dest; skipping clone."
    return 0
  fi
  echo "[$name] Cloning $repo at $ref …"
  git clone --depth 1 --branch "$ref" "$repo" "$dest"
}

fetch_repo opentui "$VENDOR_BASE/opentui"

echo "✓ Vendor fetch complete"

