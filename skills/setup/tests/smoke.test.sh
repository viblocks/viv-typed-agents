#!/usr/bin/env bash
# tests/smoke.test.sh — smoke tests for /typedAgentSetup skill lib scripts.
#
# Run from skills/setup/:
#   bash tests/smoke.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "--- Bash syntax check (lib/) ---"
shopt -s nullglob
for f in lib/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "$f syntax"; else ko "$f syntax"; fi
done

echo
echo "--- detect-state.sh ---"
FIXTURES="$REPO_ROOT/tests/fixtures"
if [ -x lib/detect-state.sh ]; then
  out=$(bash lib/detect-state.sh "$FIXTURES/greenfield")
  [ "$out" = "greenfield" ] && ok "greenfield detected" || ko "expected greenfield, got '$out'"
  out=$(bash lib/detect-state.sh "$FIXTURES/brownfield-crypto")
  [ "$out" = "brownfield" ] && ok "brownfield detected" || ko "expected brownfield, got '$out'"
else
  ko "lib/detect-state.sh not found"
fi

echo
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
