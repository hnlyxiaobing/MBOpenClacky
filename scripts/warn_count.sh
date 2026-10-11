#!/usr/bin/env bash
# Fail the build when the MoonBit compiler emits warnings.
#
# The project holds a zero-warning baseline, so this is a gate rather than a
# report: CI runs it right after `moon check`. An explicit budget argument is
# kept for the rare case where the baseline must move temporarily.
#
# Usage:
#   scripts/warn_count.sh [ALLOWED]                 run `moon check` and count
#   scripts/warn_count.sh --log <file> [ALLOWED]    count a captured check log
#
# --log lets CI reuse the output its type-check step already teed, instead of
# paying for a second full `moon check`.
set -uo pipefail

ALLOWED="0"
LOG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --log)
      if [ $# -lt 2 ]; then
        echo "warn_count: --log requires a file argument" >&2
        exit 2
      fi
      LOG="$2"
      shift 2
      ;;
    --log=*)
      LOG="${1#--log=}"
      shift
      ;;
    *)
      ALLOWED="$1"
      shift
      ;;
  esac
done

if [ -n "$LOG" ]; then
  if [ ! -f "$LOG" ]; then
    echo "warn_count: log not found: $LOG" >&2
    exit 2
  fi
  COUNT="$(grep -c 'Warning: \[' "$LOG" || true)"
  SOURCE="from $LOG"
else
  COUNT="$(moon check 2>&1 | grep -c 'Warning: \[' || true)"
  SOURCE="from a fresh moon check"
fi

echo "MoonBit warnings: ${COUNT} (budget ${ALLOWED}; ${SOURCE})"
if [ "$COUNT" -gt "$ALLOWED" ]; then
  echo "FAIL: ${COUNT} warnings exceeds the budget of ${ALLOWED}." >&2
  echo "      'moon check' prints the offending sites; fix them rather than" >&2
  echo "      raising the budget." >&2
  exit 1
fi
echo "OK: warning budget respected."
