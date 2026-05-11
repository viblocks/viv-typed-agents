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
echo "--- lookup-agent.sh ---"
if [ -x lib/lookup-agent.sh ]; then
  AGENTS="$FIXTURES/_agents"
  out=$(bash lib/lookup-agent.sh "$AGENTS" backend crypto implementer)
  [ "$out" = "backend-crypto-implementer" ] && ok "lookup backend/crypto/implementer" || ko "got: $out"
  out=$(bash lib/lookup-agent.sh "$AGENTS" frontend crypto implementer)
  [ "$out" = "frontend-crypto-implementer" ] && ok "lookup frontend/crypto/implementer" || ko "got: $out"
  if bash lib/lookup-agent.sh "$AGENTS" frontend waas implementer 2>/dev/null; then
    ko "missing agent should exit non-zero"
  else
    ok "missing agent exits non-zero"
  fi
else
  ko "lib/lookup-agent.sh not found"
fi

echo
echo "--- write-routing.sh ---"
if [ -x lib/write-routing.sh ]; then
  TMP=$(mktemp -d)
  PLAN=$(mktemp)
  cat > "$PLAN" <<'EOF'
[
  {"domain":"backend","paths":["services/core/**"],"implementer":"backend-crypto-implementer","reviewer":"backend-crypto-reviewer","enforced":true},
  {"domain":"frontend","paths":["services/ui/**"],"implementer":"frontend-crypto-implementer","reviewer":"frontend-crypto-reviewer","enforced":true}
]
EOF
  bash lib/write-routing.sh "$TMP/routing-table.json" "$PLAN"
  count=$(jq '.routes | length' "$TMP/routing-table.json")
  [ "$count" = "2" ] && ok "write fresh routing-table" || ko "expected 2 routes, got $count"

  # Idempotency: re-running should not duplicate.
  bash lib/write-routing.sh "$TMP/routing-table.json" "$PLAN"
  count=$(jq '.routes | length' "$TMP/routing-table.json")
  [ "$count" = "2" ] && ok "idempotent re-run" || ko "expected 2 routes after re-run, got $count"
  rm -rf "$TMP" "$PLAN"
else
  ko "lib/write-routing.sh not found"
fi

echo
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
