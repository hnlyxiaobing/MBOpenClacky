#!/usr/bin/env bash
# Count MoonBit compiler warnings from `moon check` and report against a
# budget. Part of spec P2-3 (Warnings reduction): establishes a CI warning
# threshold gate so regressions are visible and the budget can be tightened.
#
# Usage: scripts/warn_count.sh [ALLOWED] [STRICT]
#   ALLOWED : warning ceiling to compare against (default 200, the P2-3 target)
#   STRICT  : if the literal string "strict", exit non-zero when over budget
#
# By default the script only REPORTS (exit 0) so it never breaks CI on its
# own; set STRICT=strict once the codebase is below the budget to enforce it.
set -uo pipefail

ALLOWED="${1:-200}"
STRICT="${2:-}"

OUT="$(moon check 2>&1 || true)"
COUNT="$(printf '%s\n' "$OUT" | grep -c 'Warning: \[' || true)"

echo "MoonBit warning count: ${COUNT}"
echo "Configured budget   : ${ALLOWED}"

if [ "$COUNT" -gt "$ALLOWED" ]; then
  echo "WARNING: warning count ${COUNT} exceeds budget ${ALLOWED} (P2-3 target is <=200)."
  echo "         Safe reductions (StringView .to_string()->.to_owned(), unused imports)"
  echo "         are tracked in specs/completed; risky categories (derive(Show),"
  echo "         reserved-keyword renames in serialized structs, and the 35 external"
  echo "         .mooncakes/crescent annotations) require test-gated refactoring."
  if [ "$STRICT" = "strict" ]; then
    echo "STRICT mode: failing."
    exit 1
  fi
else
  echo "OK: warning count within budget."
fi
exit 0
