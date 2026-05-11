#!/usr/bin/env bash
# tests/smoke.test.sh — smoke tests for /typedAgentSetup skill lib scripts.
#
# Run from skills/setup/:
#   bash tests/smoke.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)" || { echo "FATAL: cannot resolve REPO_ROOT" >&2; exit 1; }
cd "$REPO_ROOT" || { echo "FATAL: cd $REPO_ROOT failed" >&2; exit 1; }

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
  out=$(bash lib/detect-state.sh "$FIXTURES/brownfield-ts-only")
  [ "$out" = "brownfield" ] && ok "brownfield-ts-only detected via .ts extension" || ko "expected brownfield, got '$out'"
else
  ko "lib/detect-state.sh not found"
fi

echo
echo "--- discover-services.sh ---"
if [ -x lib/discover-services.sh ]; then
  out=$(bash lib/discover-services.sh "$FIXTURES/brownfield-crypto" | sort)
  expected="services/core
services/ui"
  [ "$out" = "$expected" ] && ok "brownfield-crypto services discovered" || ko "got: $out"
  out=$(bash lib/discover-services.sh "$FIXTURES/greenfield")
  [ -z "$out" ] && ok "greenfield: no services" || ko "expected empty, got: $out"
else
  ko "lib/discover-services.sh not found"
fi

echo
echo "--- classify-layer.sh ---"
if [ -x lib/classify-layer.sh ]; then
  SKILLS="$FIXTURES/_skills"
  out=$(bash lib/classify-layer.sh "$FIXTURES/brownfield-crypto" "services/core" "$SKILLS")
  [ "$out" = "backend" ] && ok "services/core -> backend" || ko "got: $out"
  out=$(bash lib/classify-layer.sh "$FIXTURES/brownfield-crypto" "services/ui" "$SKILLS")
  [ "$out" = "frontend" ] && ok "services/ui -> frontend" || ko "got: $out"
else
  ko "lib/classify-layer.sh not found"
fi

echo
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
