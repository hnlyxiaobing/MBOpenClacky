#!/usr/bin/env bash
set -euo pipefail

# OneBit-TUI Post-Install Script
# Fetches vendor dependencies and builds native library if needed

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[onebit-tui] Checking dependencies..."

# Fetch vendor dependencies if needed
if [ ! -d "$ROOT_DIR/src/ffi/vendor/opentui" ]; then
  echo "[onebit-tui] Fetching vendor dependencies..."
  if [ -f "$ROOT_DIR/scripts/vendor_fetch.sh" ]; then
    bash "$ROOT_DIR/scripts/vendor_fetch.sh" || {
      echo "[onebit-tui] Warning: Failed to fetch vendor dependencies"
      echo "  You may need to run: ./scripts/vendor_fetch.sh manually"
    }
  fi
else
  echo "[onebit-tui] Vendor dependencies present."
fi

# Check if FFI library exists
if [ ! -f "$ROOT_DIR/src/ffi/lib/libopentui.a" ]; then
  echo "[onebit-tui] Native library not found."
  
  # Only build if we're not in CI and have the tools
  if [ -z "${CI:-}" ] && command -v zig &> /dev/null 2>&1; then
    echo "[onebit-tui] Building native renderer..."
    if [ -f "$ROOT_DIR/build_ffi.sh" ]; then
      (cd "$ROOT_DIR" && ./build_ffi.sh) || {
        echo "[onebit-tui] Warning: Failed to build native library"
        echo "  You may need to run: ./build_ffi.sh manually"
      }
    fi
  else
    echo "[onebit-tui] Note: Native library needs to be built"
    echo "  Run: cd $ROOT_DIR && ./build_ffi.sh"
  fi
else
  echo "[onebit-tui] Native library present."
fi

echo "[onebit-tui] Setup complete!"
exit 0