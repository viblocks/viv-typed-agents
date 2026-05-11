#!/usr/bin/env bash
# e2e.test.sh — end-to-end test of /typedAgentSetup lib scripts on the
# brownfield-crypto fixture. Simulates the SKILL.md orchestration without
# the LLM conversation.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="$REPO_ROOT/tests/fixtures/brownfield-crypto"
SKILLS="$REPO_ROOT/tests/fixtures/_skills"
AGENTS="$REPO_ROOT/tests/fixtures/_agents"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

state=$(bash lib/detect-state.sh "$PROJECT")
[ "$state" = "brownfield" ] || { echo "FAIL: state=$state"; exit 1; }

services=$(bash lib/discover-services.sh "$PROJECT" | sort)
[ "$services" = "services/core
services/ui" ] || { echo "FAIL: services=$services"; exit 1; }

backend_impl=$(bash lib/lookup-agent.sh "$AGENTS" backend crypto implementer)
frontend_impl=$(bash lib/lookup-agent.sh "$AGENTS" frontend crypto implementer)

cat > "$TMP/plan.json" <<EOF
[
  {"domain":"backend","paths":["services/core/**"],"implementer":"$backend_impl","reviewer":"backend-crypto-reviewer","enforced":true},
  {"domain":"frontend","paths":["services/ui/**"],"implementer":"$frontend_impl","reviewer":"frontend-crypto-reviewer","enforced":true}
]
EOF

bash lib/write-routing.sh "$TMP/routing-table.json" "$TMP/plan.json"

if diff <(jq -S . "$TMP/routing-table.json") <(jq -S . "$PROJECT/expected-routing.json") >/dev/null; then
  echo "PASS: brownfield-crypto e2e matches golden output"
else
  echo "FAIL: routing-table does not match golden"
  diff <(jq -S . "$TMP/routing-table.json") <(jq -S . "$PROJECT/expected-routing.json")
  exit 1
fi
