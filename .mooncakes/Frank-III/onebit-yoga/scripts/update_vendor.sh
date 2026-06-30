#!/usr/bin/env bash
set -euo pipefail

# Update a vendored dependency to a specific ref
# Usage: update_vendor.sh yoga <ref>

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/scripts/vendor.lock"
VENDOR_BASE="$ROOT_DIR/src/ffi/vendor"

NAME="${1:-}"
REF="${2:-}"

if [ -z "$NAME" ] || [ -z "$REF" ]; then
  echo "Usage: $0 <name> <ref>" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required to update vendor.lock" >&2
  exit 1
fi

python3 - "$LOCK_FILE" "$NAME" "$REF" <<'PY'
import json,sys
lock_path, name, ref = sys.argv[1:4]
with open(lock_path) as f:
    data = json.load(f)
if name not in data:
    print(f"Unknown vendor entry: {name}")
    sys.exit(1)
data[name]['ref'] = ref
with open(lock_path,'w') as f:
    json.dump(data,f,indent=2)
print(f"Updated {name} to {ref}")
PY

DEST="$VENDOR_BASE/$NAME"
if [ -d "$DEST/.git" ]; then
  echo "Updating $NAME checkout …"
  git -C "$DEST" fetch --depth 1 origin "$REF"
  git -C "$DEST" checkout -q FETCH_HEAD
else
  echo "$NAME not present under $DEST; run scripts/vendor_fetch.sh first."
fi

echo "✓ Vendor $NAME updated"

