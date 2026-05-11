#!/usr/bin/env bash
# uninstall.test.sh — install + (simulated wizard) + uninstall round-trip.
# Verifies: typed-agents content gone, user content preserved, manifest cleaned.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Plant a user customization that must SURVIVE uninstall.
mkdir -p "$TMP/.claude/skills/my-team-skill"
echo "# My team's custom skill" > "$TMP/.claude/skills/my-team-skill/SKILL.md"

# Plant a user CLAUDE.md.
cat > "$TMP/CLAUDE.md" <<'EOF'
# Existing project rules
This must survive uninstall.
EOF

# Plant a user settings.json key.
mkdir -p "$TMP/.claude"
echo '{"theme":"dark"}' > "$TMP/.claude/settings.json"

echo "--- Install tier 5 ---"
bash "$REPO_ROOT/scripts/install.sh" "$TMP" --tier 5 >/dev/null 2>&1

# Verify manifest emitted.
[ -f "$TMP/.claude/.install-manifest.json" ] && ok "install manifest created" || ko "no manifest"

# Verify special-case viv-hooks paths captured.
jq -e '.components."viv-hooks".paths | index(".claude/lib")' "$TMP/.claude/.install-manifest.json" >/dev/null \
  && ok "viv-hooks manifest includes .claude/lib" || ko "missing .claude/lib"

# Simulate the wizard: merge settings + append CLAUDE.md block.
bash "$TMP/.claude/skills/setup/lib/merge-settings.sh" \
     "$TMP/.claude/settings.json" \
     "$TMP/.claude/hooks/settings.json.fragment"
bash "$TMP/.claude/skills/setup/lib/adapt-claude-md.sh" \
     "$TMP/.claude/orchestration/CLAUDE.template.md" \
     "$TMP/CLAUDE.md" "test-app"

echo ""
echo "--- Full uninstall ---"
bash "$REPO_ROOT/scripts/uninstall.sh" "$TMP" >/dev/null 2>&1

# typed-agents directories should be gone.
[ ! -d "$TMP/.claude/agents" ] && ok "viv-agents removed" || ko "viv-agents remains"
[ ! -d "$TMP/.claude/hooks" ]  && ok "viv-hooks removed"  || ko "viv-hooks remains"
[ ! -d "$TMP/.claude/lib" ]    && ok ".claude/lib removed (viv-hooks sibling)" || ko ".claude/lib remains"
[ ! -d "$TMP/.claude/orchestration" ] && ok "viv-orchestration-rules removed" || ko "orchestration remains"
[ ! -f "$TMP/.claude/.install-manifest.json" ] && ok "manifest removed" || ko "manifest remains"

# User customization MUST survive.
[ -f "$TMP/.claude/skills/my-team-skill/SKILL.md" ] && ok "user custom skill preserved" \
  || ko "user custom skill DESTROYED"

# User CLAUDE.md content MUST survive (above the (removed) managed block).
grep -qF "# Existing project rules" "$TMP/CLAUDE.md" && ok "user CLAUDE.md content preserved" \
  || ko "user CLAUDE.md content lost"

# User CLAUDE.md should NOT contain the managed block anymore.
! grep -qF "viv-typed-agents:BEGIN" "$TMP/CLAUDE.md" && ok "managed block removed from CLAUDE.md" \
  || ko "managed block still present"

# User settings.json key MUST survive.
[ "$(jq -r .theme "$TMP/.claude/settings.json" 2>/dev/null)" = "dark" ] && ok "user theme key preserved" \
  || ko "user theme key lost"

echo ""
echo "--- Partial uninstall (--components viv-hooks) ---"
rm -rf "$TMP"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

bash "$REPO_ROOT/scripts/install.sh" "$TMP" --tier 5 >/dev/null 2>&1
bash "$TMP/.claude/skills/setup/lib/merge-settings.sh" \
     "$TMP/.claude/settings.json" \
     "$TMP/.claude/hooks/settings.json.fragment"
cat > "$TMP/CLAUDE.md" <<'EOF'
# user content above
<!-- viv-typed-agents:BEGIN -->
managed
<!-- viv-typed-agents:END -->
EOF

settings_before=$(md5 -q "$TMP/.claude/settings.json" 2>/dev/null || md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)
claudemd_before=$(md5 -q "$TMP/CLAUDE.md" 2>/dev/null || md5sum "$TMP/CLAUDE.md" | cut -d' ' -f1)

bash "$REPO_ROOT/scripts/uninstall.sh" "$TMP" --components viv-hooks >/dev/null 2>&1

[ ! -d "$TMP/.claude/hooks" ] && ok "partial: viv-hooks removed" || ko "viv-hooks remains"
[ ! -d "$TMP/.claude/lib" ]   && ok "partial: .claude/lib removed" || ko ".claude/lib remains"

[ -d "$TMP/.claude/agents" ]        && ok "partial: viv-agents preserved" || ko "agents removed unexpectedly"
[ -d "$TMP/.claude/orchestration" ] && ok "partial: orchestration preserved" || ko "orchestration removed unexpectedly"

settings_after=$(md5 -q "$TMP/.claude/settings.json" 2>/dev/null || md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)
claudemd_after=$(md5 -q "$TMP/CLAUDE.md" 2>/dev/null || md5sum "$TMP/CLAUDE.md" | cut -d' ' -f1)
[ "$settings_before" = "$settings_after" ] && ok "partial: settings.json untouched" || ko "settings.json modified by partial"
[ "$claudemd_before" = "$claudemd_after" ] && ok "partial: CLAUDE.md untouched"   || ko "CLAUDE.md modified by partial"

jq -e '.components | has("viv-hooks") | not' "$TMP/.claude/.install-manifest.json" >/dev/null \
  && ok "partial: manifest rewritten without viv-hooks" || ko "manifest still lists viv-hooks"
jq -e '.components | has("viv-agents")' "$TMP/.claude/.install-manifest.json" >/dev/null \
  && ok "partial: manifest preserves viv-agents" || ko "manifest dropped viv-agents"

echo ""
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
