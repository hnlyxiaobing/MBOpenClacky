#!/usr/bin/env bash
# Fail the build when the MoonBit compiler emits warnings.
#
# The project holds a zero-warning baseline, so this is a gate rather than a
# report: CI runs it right after `moon check`. An explicit budget argument is
# kept for the rare case where the baseline must move temporarily.
#
# Usage: scripts/warn_count.sh [ALLOWED]     (default: 0)
set -uo pipefail

ALLOWED="${1:-0}"
COUNT="$(moon check 2>&1 | grep -c 'Warning: \[' || true)"

echo "MoonBit warnings: ${COUNT} (budget ${ALLOWED})"
if [ "$COUNT" -gt "$ALLOWED" ]; then
  echo "FAIL: ${COUNT} warnings exceeds the budget of ${ALLOWED}." >&2
  echo "      'moon check' prints the offending sites; fix them rather than" >&2
  echo "      raising the budget." >&2
  exit 1
fi
echo "OK: warning budget respected."
