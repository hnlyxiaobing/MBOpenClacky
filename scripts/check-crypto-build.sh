#!/usr/bin/env bash
# Guard against shipping the insecure crypto stubs in a release build.
#
# The weak stubs in lib/brand/brand_stubs.c are compiled ONLY when the build is
# configured with -DMBOPENCLACKY_NO_OPENSSL. That path provides deterministic but
# cryptographically broken primitives (non-random nonces, all-zero ciphertext)
# and must never reach a release / production artifact.
#
# This is a CI / developer build-time safety net: it refuses a RELEASE build when
# MBOPENCLACKY_NO_OPENSSL is set (unless explicitly overridden), and warns for
# debug builds. The C layer in brand_stubs.c enforces the same rule at compile
# time via the MBOPENCLACKY_INSECURE_DEBUG_BUILD acknowledgement flag.
#
# Usage:
#   ./scripts/check-crypto-build.sh [release|debug]
#
# Exit codes:
#   0 -> safe to proceed
#   1 -> forbidden combination (release + insecure stubs)
set -euo pipefail

BUILD_KIND="${1:-release}"

if [ -n "${MBOPENCLACKY_NO_OPENSSL:-}" ]; then
  if [ "$BUILD_KIND" = "release" ] && [ -z "${MBOPENCLACKY_INSECURE_OK:-}" ]; then
    echo "ERROR: Refusing to build RELEASE with MBOPENCLACKY_NO_OPENSSL." >&2
    echo "       This would ship the insecure crypto stubs (non-random nonces," >&2
    echo "       all-zero ciphertext) from lib/brand/brand_stubs.c." >&2
    echo "       Drop -DMBOPENCLACKY_NO_OPENSSL, or — for a debug-only minimal" >&2
    echo "       build — set MBOPENCLACKY_INSECURE_OK=1 AND MBOPENCLACKY_INSECURE_DEBUG_BUILD=1." >&2
    exit 1
  fi
  echo "WARNING: Building with MBOPENCLACKY_NO_OPENSSL (insecure crypto stubs)." >&2
  echo "         Not for production use." >&2
fi

echo "OK: crypto build guard passed (kind=$BUILD_KIND)."
