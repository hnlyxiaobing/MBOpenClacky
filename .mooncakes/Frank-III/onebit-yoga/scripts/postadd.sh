#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$ROOT_DIR/src/ffi/vendor/yoga" ]; then
  echo "[onebit-yoga] Vendor not found; fetching …"
  bash "$ROOT_DIR/scripts/vendor_fetch.sh" || true
else
  echo "[onebit-yoga] Vendor present; nothing to do."
fi

# Build native libraries if missing and toolchain is available
LIB_WRAP="$ROOT_DIR/src/ffi/libyoga_wrap.a"
LIB_CORE="$ROOT_DIR/src/ffi/yoga-install/lib/libyogacore.a"
if [ -f "$LIB_WRAP" ] && [ -f "$LIB_CORE" ]; then
  echo "[onebit-yoga] Native libraries present."
else
  if command -v cmake >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    echo "[onebit-yoga] Building native Yoga libraries …"
    (cd "$ROOT_DIR/src/ffi" && bash scripts/build_yoga.sh) || {
      echo "[onebit-yoga] Warning: Failed to build Yoga native libraries"
      echo "  You may need to run: (cd .mooncakes/Frank-III/onebit-yoga/src/ffi && bash scripts/build_yoga.sh)"
    }
  else
    echo "[onebit-yoga] Toolchain not available (cmake/make). Skipping native build."
  fi
fi

exit 0
