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
echo "--- classify-layer.sh: realistic monorepo ---"
if [ -x lib/classify-layer.sh ]; then
  SKILLS="$FIXTURES/_skills"
  # services/core: main.ts lives in src/ (not root) and nest-cli.json is absent,
  # so entry_files miss — must fall through to file_globs (src/**/*.module.ts).
  out=$(bash lib/classify-layer.sh "$FIXTURES/brownfield-realistic" "services/core" "$SKILLS")
  [ "$out" = "backend" ] && ok "realistic/services/core -> backend via glob" || ko "got: $out"
  out=$(bash lib/classify-layer.sh "$FIXTURES/brownfield-realistic" "services/ui" "$SKILLS")
  [ "$out" = "frontend" ] && ok "realistic/services/ui -> frontend" || ko "got: $out"

  # Regression: a backend folder containing a stray .tsx file (e.g. email
  # template) matches BOTH backend (src/**/*.module.ts) and frontend
  # (**/*.tsx). This validates that the new precise glob matching surfaces
  # real ambiguity rather than silently picking a wrong layer — the wizard
  # is expected to ask the user when it sees `ambiguous`.
  out=$(bash lib/classify-layer.sh "$FIXTURES/brownfield-backend-with-stray-tsx" "services/core" "$SKILLS")
  [ "$out" = "ambiguous" ] && ok "backend + stray .tsx correctly flagged ambiguous" || ko "got: $out (expected ambiguous, model needs work)"
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
echo "--- merge-settings.sh ---"
if [ -x lib/merge-settings.sh ]; then
  TMP=$(mktemp -d)
  echo '{"theme":"dark","hooks":{"PreToolUse":[]}}' > "$TMP/settings.json"
  echo '{"hooks":{"PreToolUse":[{"name":"deny-class-a"}]}}' > "$TMP/fragment.json"
  bash lib/merge-settings.sh "$TMP/settings.json" "$TMP/fragment.json"
  theme=$(jq -r '.theme' "$TMP/settings.json")
  hooks=$(jq '.hooks.PreToolUse | length' "$TMP/settings.json")
  [ "$theme" = "dark" ] && [ "$hooks" = "1" ] && ok "merge preserves user keys and adds hook" || ko "theme=$theme hooks=$hooks"
  rm -rf "$TMP"
else
  ko "lib/merge-settings.sh not found"
fi

echo
echo "--- adapt-claude-md.sh ---"
if [ -x lib/adapt-claude-md.sh ]; then
  TMP=$(mktemp -d)
  echo "# <PROJECT_NAME>" > "$TMP/template.md"

  # Mode 1: fresh file
  bash lib/adapt-claude-md.sh "$TMP/template.md" "$TMP/CLAUDE.md" "viv-app"
  grep -qF "<!-- viv-typed-agents:BEGIN -->" "$TMP/CLAUDE.md" && \
  grep -qF "# viv-app" "$TMP/CLAUDE.md" && \
  grep -qF "<!-- viv-typed-agents:END -->" "$TMP/CLAUDE.md" && \
    ok "mode 1: fresh file created with managed block" || ko "mode 1 failed"

  # Mode 2: existing file without markers → append
  echo "# Existing content" > "$TMP/CLAUDE.md"
  bash lib/adapt-claude-md.sh "$TMP/template.md" "$TMP/CLAUDE.md" "viv-app"
  head -1 "$TMP/CLAUDE.md" | grep -qF "Existing content" && \
  grep -qF "<!-- viv-typed-agents:BEGIN -->" "$TMP/CLAUDE.md" && \
  grep -qF "# viv-app" "$TMP/CLAUDE.md" && \
    ok "mode 2: existing file preserved + managed block appended" || ko "mode 2 failed"

  # Mode 3: re-running should replace, not duplicate
  bash lib/adapt-claude-md.sh "$TMP/template.md" "$TMP/CLAUDE.md" "viv-app"
  begin_count=$(grep -cF "<!-- viv-typed-agents:BEGIN -->" "$TMP/CLAUDE.md")
  end_count=$(grep -cF "<!-- viv-typed-agents:END -->" "$TMP/CLAUDE.md")
  [ "$begin_count" = "1" ] && [ "$end_count" = "1" ] && \
    ok "mode 3: idempotent re-run (no duplicate markers)" || ko "mode 3 failed: begin=$begin_count end=$end_count"

  # Mode 3: refresh with new project name
  echo "# template-v2 <PROJECT_NAME>" > "$TMP/template.md"
  bash lib/adapt-claude-md.sh "$TMP/template.md" "$TMP/CLAUDE.md" "renamed-app"
  grep -qF "# template-v2 renamed-app" "$TMP/CLAUDE.md" && \
  ! grep -qF "# viv-app" "$TMP/CLAUDE.md" && \
    ok "mode 3: template content refreshed on re-run" || ko "mode 3 refresh failed"

  # Mode 2/3: content above markers preserved verbatim
  head -1 "$TMP/CLAUDE.md" | grep -qF "Existing content" && \
    ok "content outside markers preserved across all modes" || ko "outside content lost"
  rm -rf "$TMP"
else
  ko "lib/adapt-claude-md.sh not found"
fi

echo
echo "--- unmerge-settings.sh ---"
if [ -x lib/unmerge-settings.sh ]; then
  TMP=$(mktemp -d)
  echo '{"theme":"dark","hooks":{"PreToolUse":[{"name":"deny-class-a"},{"name":"user-custom-hook"}]}}' > "$TMP/settings.json"
  echo '{"hooks":{"PreToolUse":[{"name":"deny-class-a"}]}}' > "$TMP/fragment.json"
  bash lib/unmerge-settings.sh "$TMP/settings.json" "$TMP/fragment.json"
  theme=$(jq -r '.theme' "$TMP/settings.json")
  hooks_len=$(jq '.hooks.PreToolUse | length' "$TMP/settings.json")
  hook_name=$(jq -r '.hooks.PreToolUse[0].name' "$TMP/settings.json")
  if [ "$theme" = "dark" ] && [ "$hooks_len" = "1" ] && [ "$hook_name" = "user-custom-hook" ]; then
    ok "unmerge: user keys preserved + fragment entry removed"
  else
    ko "unmerge failed (theme=$theme hooks_len=$hooks_len hook_name=$hook_name)"
  fi

  prev=$(md5 -q "$TMP/settings.json" 2>/dev/null || md5sum "$TMP/settings.json" | cut -d' ' -f1)
  bash lib/unmerge-settings.sh "$TMP/settings.json" "$TMP/fragment.json"
  next=$(md5 -q "$TMP/settings.json" 2>/dev/null || md5sum "$TMP/settings.json" | cut -d' ' -f1)
  [ "$prev" = "$next" ] && ok "unmerge idempotent" || ko "unmerge not idempotent"

  echo '{"hooks":{"PreToolUse":[{"name":"deny-class-a"}]}}' > "$TMP/settings.json"
  bash lib/unmerge-settings.sh "$TMP/settings.json" "$TMP/fragment.json"
  [ ! -f "$TMP/settings.json" ] && ok "unmerge: empty {} → file removed" || ko "empty unmerge failed"

  rm -rf "$TMP"
else
  ko "lib/unmerge-settings.sh not found"
fi

echo
echo "--- unmark-claude-md.sh ---"
if [ -x lib/unmark-claude-md.sh ]; then
  TMP=$(mktemp -d)

  cat > "$TMP/CLAUDE.md" <<'EOF'
# Project conventions
Some user content above.
<!-- viv-typed-agents:BEGIN -->
Managed content here.
<!-- viv-typed-agents:END -->
More user content below.
EOF
  bash lib/unmark-claude-md.sh "$TMP/CLAUDE.md"
  if grep -qF "Project conventions" "$TMP/CLAUDE.md" \
     && grep -qF "More user content below" "$TMP/CLAUDE.md" \
     && ! grep -qF "Managed content here" "$TMP/CLAUDE.md" \
     && ! grep -qF "viv-typed-agents:BEGIN" "$TMP/CLAUDE.md"; then
    ok "unmark: block removed, content outside preserved"
  else
    ko "unmark removal failed"
  fi

  prev=$(cat "$TMP/CLAUDE.md")
  bash lib/unmark-claude-md.sh "$TMP/CLAUDE.md"
  [ "$(cat "$TMP/CLAUDE.md")" = "$prev" ] && ok "unmark idempotent" || ko "unmark not idempotent"

  cat > "$TMP/CLAUDE.md" <<'EOF'
<!-- viv-typed-agents:BEGIN -->
only managed
<!-- viv-typed-agents:END -->
EOF
  bash lib/unmark-claude-md.sh "$TMP/CLAUDE.md" --remove-if-empty
  [ ! -f "$TMP/CLAUDE.md" ] && ok "unmark --remove-if-empty deletes empty file" || ko "remove-if-empty failed"

  rm -rf "$TMP"
else
  ko "lib/unmark-claude-md.sh not found"
fi

echo
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
