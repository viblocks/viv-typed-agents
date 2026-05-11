# Uninstall Flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a turnkey uninstaller (`scripts/uninstall.sh`) that removes a `viv-typed-agents` installation from a consumer project while preserving user customizations. Backed by an install manifest (`.install-manifest.json`) emitted by `install.sh`.

**Architecture:** Two sequential PRs in `viv-typed-agents`. PR-1 modifies `install.sh` to emit a per-component manifest of deployed paths (source-side enumeration, robust to re-install). PR-2 adds `scripts/uninstall.sh` plus two new lib scripts (`unmerge-settings.sh`, `unmark-claude-md.sh`) and an e2e round-trip test. Wizard outputs (`settings.json` reverse-merge + `CLAUDE.md` unmark) only run on full uninstall, never on partial.

**Tech Stack:** Bash 3.2+ (macOS-portable), `jq`, `yq`, GNU/BSD `find`.

**Reference spec:** `architecture/specs/2026-05-11-uninstall.md`

**Repo:** `/Users/viv/AI/vault/viv-typed-agents` (single repo, no cross-repo dependencies for this feature).

---

## Phase 1 — PR-1: Install manifest

### Task 1: Add manifest infrastructure to install.sh

**Files:**
- Modify: `scripts/install.sh` (top of script, near other globals around line 30-80)

- [ ] **Step 1: Open a feature branch**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git checkout main && git pull --ff-only
git checkout -b feat/install-manifest
```

- [ ] **Step 2: Add manifest helpers near the top of install.sh**

After the existing global variables (around the line that says `MANIFEST="$REPO_ROOT/MANIFEST.yaml"`), insert this block:

```bash
# ---- Install manifest (for uninstall) ----
# As each component deploys, register the destination paths it owns.
# Paths are relative to $TARGET. The manifest is written at the end.
declare -a INSTALL_MANIFEST_ENTRIES  # one "comp<TAB>relpath" per line

install_manifest_register() {
  local comp="$1" relpath="$2"
  # Strip any duplicate leading/trailing slash
  relpath="${relpath#/}"; relpath="${relpath%/}"
  INSTALL_MANIFEST_ENTRIES+=("$comp"$'\t'"$relpath")
}

install_manifest_emit() {
  # Write $TARGET/.claude/.install-manifest.json grouping registered paths
  # by component, with commit SHA and timestamp.
  local out="$TARGET/.claude/.install-manifest.json"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$TARGET/.claude"
  # Build {comp: [paths...]} via jq from the entries array.
  local jq_input
  jq_input=$(printf '%s\n' "${INSTALL_MANIFEST_ENTRIES[@]:-}" | jq -R -s '
    split("\n")
    | map(select(length > 0))
    | map(split("\t") | {comp: .[0], path: .[1]})
    | group_by(.comp)
    | map({key: .[0].comp, value: {paths: map(.path)}})
    | from_entries
  ')
  # Attach the commit SHA from MANIFEST.yaml for each component (and "<self>" pass-through).
  local comps; comps=$(echo "$jq_input" | jq -r 'keys[]')
  for c in $comps; do
    local sha; sha=$(yq eval ".components.\"$c\".commit" "$MANIFEST")
    jq_input=$(echo "$jq_input" | jq --arg c "$c" --arg sha "$sha" '.[$c].commit = $sha')
  done
  echo "$jq_input" | jq --arg ts "$ts" --argjson tier "$TIER" '{
    schema_version: "1.0",
    installed_at: $ts,
    tier: $tier,
    components: .
  }' > "$out"
  echo "    ✓ manifest written to .claude/.install-manifest.json"
}
```

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n scripts/install.sh && echo "OK syntax"
```
Expected: `OK syntax`.

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): add manifest infrastructure (register + emit helpers)

Defines INSTALL_MANIFEST_ENTRIES array plus install_manifest_register
and install_manifest_emit helpers. Subsequent commits wire the helpers
into each per-component deploy branch."
```

---

### Task 2: Wire registration into the `<self>` branch

**Files:**
- Modify: `scripts/install.sh` (the `if [ "$REPO_URL" = "<self>" ]; then` block, around lines 177-202)

- [ ] **Step 1: Locate the `<self>` branch**

```bash
grep -n '"<self>"' scripts/install.sh
```

- [ ] **Step 2: Add the register call right before `continue`**

Find the block ending with:
```bash
    cp -R "$SELF_SRC/." "$TARGET/$SELF_TARGET_REL/"
    find "$TARGET/$SELF_TARGET_REL" -name '*.sh' -type f -exec chmod +x {} \; 2>/dev/null || true
    echo "    ✓ copied from $SELF_SRC"
    continue
  fi
```

Insert ONE LINE between the `echo` and `continue`:
```bash
    install_manifest_register "$comp" "$SELF_TARGET_REL"
```

- [ ] **Step 3: Syntax check**

```bash
bash -n scripts/install.sh && echo "OK"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for <self> components"
```

---

### Task 3: Wire registration into the viv-skills case

**Files:**
- Modify: `scripts/install.sh` (the `viv-skills)` case, around lines 233-261)

- [ ] **Step 1: Read the current viv-skills case**

```bash
sed -n '/^    viv-skills)/,/^      ;;/p' scripts/install.sh
```

- [ ] **Step 2: Add register call after each `cp -r "$sub" "$DEST/"`**

The case has two paths (filtered and unfiltered). In both, after each `cp -r`, add `install_manifest_register`.

In the filtered branch, change:
```bash
        if [ -n "$found" ]; then
          cp -r "$found" "$DEST/"
          echo "    + skill: $skill"
        else
```
to:
```bash
        if [ -n "$found" ]; then
          cp -r "$found" "$DEST/"
          install_manifest_register "$comp" "$TARGET_PATH/$skill/"
          echo "    + skill: $skill"
        else
```

In the unfiltered branch, change:
```bash
          *)
            if [ -d "$sub" ]; then
              cp -r "$sub" "$DEST/"
            fi
            ;;
```
to:
```bash
          *)
            if [ -d "$sub" ]; then
              cp -r "$sub" "$DEST/"
              install_manifest_register "$comp" "$TARGET_PATH/$name/"
            fi
            ;;
```

- [ ] **Step 3: Verify with a dry-run install against a tmp dir, inspect what would be registered**

```bash
bash -n scripts/install.sh && echo "OK syntax"
```

(Full e2e verification deferred to Task 9.)

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for viv-skills deploy"
```

---

### Task 4: Wire registration into the viv-agents case

**Files:**
- Modify: `scripts/install.sh` (the `viv-agents)` case, around lines 262-295)

- [ ] **Step 1: Locate the case**

The case copies individual `.md` files. Two branches: filtered (per agent) and unfiltered (`find -exec cp {}`).

- [ ] **Step 2: Filtered branch — register each agent file**

Change:
```bash
          if [ -n "$found" ]; then
            cp "$found" "$DEST/"
            echo "    + agent: $agent"
          else
```
to:
```bash
          if [ -n "$found" ]; then
            cp "$found" "$DEST/"
            install_manifest_register "$comp" "$TARGET_PATH/${agent}.md"
            echo "    + agent: $agent"
          else
```

- [ ] **Step 3: Unfiltered branch — register every .md file copied**

The unfiltered branch uses `find ... -exec cp {} "$DEST/" \;`. Replace it with an explicit loop so we can register each:

Change:
```bash
        find "$CLONE_DIR" -maxdepth 3 -name '*.md' -type f \
          -not -path "*/.git/*" \
          -not -path "*/_shared/*" \
          -not -path "*/architecture/*" \
          -not -path "$CLONE_DIR/README.md" \
          -not -path "$CLONE_DIR/CLAUDE.md" \
          -exec cp {} "$DEST/" \;
```
to:
```bash
        while IFS= read -r src; do
          [ -f "$src" ] || continue
          cp "$src" "$DEST/"
          install_manifest_register "$comp" "$TARGET_PATH/$(basename "$src")"
        done < <(find "$CLONE_DIR" -maxdepth 3 -name '*.md' -type f \
                  -not -path "*/.git/*" \
                  -not -path "*/_shared/*" \
                  -not -path "*/architecture/*" \
                  -not -path "$CLONE_DIR/README.md" \
                  -not -path "$CLONE_DIR/CLAUDE.md")
```

- [ ] **Step 4: Syntax check**

```bash
bash -n scripts/install.sh && echo "OK"
```

- [ ] **Step 5: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for viv-agents deploy"
```

---

### Task 5: Wire registration into the viv-routing case

**Files:**
- Modify: `scripts/install.sh` (the `viv-routing)` case, around lines 296-310)

- [ ] **Step 1: Locate the case**

It copies specific files conditionally: `routing-table.json`, `schema/`, `NAMING.md`.

- [ ] **Step 2: Add register call after each conditional copy**

Change:
```bash
      if [ -f "$CLONE_DIR/examples/full-stack.routing-table.json" ]; then
        cp "$CLONE_DIR/examples/full-stack.routing-table.json" "$DEST/routing-table.json"
        sed -i.bak 's|"\$schema": "../schema/|"$schema": "./schema/|' "$DEST/routing-table.json"
        rm -f "$DEST/routing-table.json.bak"
      elif [ -f "$CLONE_DIR/routing-table.template.json" ]; then
        cp "$CLONE_DIR/routing-table.template.json" "$DEST/routing-table.json"
      fi
      [ -d "$CLONE_DIR/schema" ] && cp -r "$CLONE_DIR/schema" "$DEST/"
      [ -f "$CLONE_DIR/NAMING.md" ] && cp "$CLONE_DIR/NAMING.md" "$DEST/"
```
to:
```bash
      if [ -f "$CLONE_DIR/examples/full-stack.routing-table.json" ]; then
        cp "$CLONE_DIR/examples/full-stack.routing-table.json" "$DEST/routing-table.json"
        sed -i.bak 's|"\$schema": "../schema/|"$schema": "./schema/|' "$DEST/routing-table.json"
        rm -f "$DEST/routing-table.json.bak"
        install_manifest_register "$comp" "$TARGET_PATH/routing-table.json"
      elif [ -f "$CLONE_DIR/routing-table.template.json" ]; then
        cp "$CLONE_DIR/routing-table.template.json" "$DEST/routing-table.json"
        install_manifest_register "$comp" "$TARGET_PATH/routing-table.json"
      fi
      if [ -d "$CLONE_DIR/schema" ]; then
        cp -r "$CLONE_DIR/schema" "$DEST/"
        install_manifest_register "$comp" "$TARGET_PATH/schema/"
      fi
      if [ -f "$CLONE_DIR/NAMING.md" ]; then
        cp "$CLONE_DIR/NAMING.md" "$DEST/"
        install_manifest_register "$comp" "$TARGET_PATH/NAMING.md"
      fi
```

- [ ] **Step 3: Syntax check + commit**

```bash
bash -n scripts/install.sh
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for viv-routing deploy"
```

---

### Task 6: Wire registration into the viv-workflows case

**Files:**
- Modify: `scripts/install.sh` (the `viv-workflows)` case, around lines 311-330)

- [ ] **Step 1: Locate the case**

It copies workflow JSON files (one per rules file), schemas, and optionally examples.

- [ ] **Step 2: Add registers**

Change:
```bash
      mkdir -p "$DEST/schemas"
      if [ -d "$CLONE_DIR/rules" ]; then
        for f in "$CLONE_DIR"/rules/*.json; do
          [ -f "$f" ] || continue
          base=$(basename "$f" .template.json)
          cp "$f" "$DEST/${base}.json"
        done
      fi
      if [ -d "$CLONE_DIR/schemas" ]; then
        cp -r "$CLONE_DIR"/schemas/* "$DEST/schemas/"
      fi
      if [ -d "$CLONE_DIR/examples/viblocks-style" ]; then
        mkdir -p "$DEST/examples/viblocks-style"
        cp -r "$CLONE_DIR"/examples/viblocks-style/* "$DEST/examples/viblocks-style/"
      fi
```
to:
```bash
      mkdir -p "$DEST/schemas"
      install_manifest_register "$comp" "$TARGET_PATH/schemas/"
      if [ -d "$CLONE_DIR/rules" ]; then
        for f in "$CLONE_DIR"/rules/*.json; do
          [ -f "$f" ] || continue
          base=$(basename "$f" .template.json)
          cp "$f" "$DEST/${base}.json"
          install_manifest_register "$comp" "$TARGET_PATH/${base}.json"
        done
      fi
      if [ -d "$CLONE_DIR/schemas" ]; then
        cp -r "$CLONE_DIR"/schemas/* "$DEST/schemas/"
      fi
      if [ -d "$CLONE_DIR/examples/viblocks-style" ]; then
        mkdir -p "$DEST/examples/viblocks-style"
        cp -r "$CLONE_DIR"/examples/viblocks-style/* "$DEST/examples/viblocks-style/"
        install_manifest_register "$comp" "$TARGET_PATH/examples/"
      fi
```

- [ ] **Step 3: Syntax check + commit**

```bash
bash -n scripts/install.sh
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for viv-workflows deploy"
```

---

### Task 7: Wire registration into the viv-orchestration-rules case

**Files:**
- Modify: `scripts/install.sh` (the `viv-orchestration-rules)` case, around lines 331-335)

- [ ] **Step 1: Update the case**

Change:
```bash
      [ -f "$CLONE_DIR/CLAUDE.template.md" ] && cp "$CLONE_DIR/CLAUDE.template.md" "$DEST/"
      [ -d "$CLONE_DIR/playbooks" ] && cp -r "$CLONE_DIR/playbooks" "$DEST/"
```
to:
```bash
      if [ -f "$CLONE_DIR/CLAUDE.template.md" ]; then
        cp "$CLONE_DIR/CLAUDE.template.md" "$DEST/"
        install_manifest_register "$comp" "$TARGET_PATH/CLAUDE.template.md"
      fi
      if [ -d "$CLONE_DIR/playbooks" ]; then
        cp -r "$CLONE_DIR/playbooks" "$DEST/"
        install_manifest_register "$comp" "$TARGET_PATH/playbooks/"
      fi
      # Newer revisions of viv-orchestration-rules also ship a rules/ subdir.
      if [ -d "$CLONE_DIR/rules" ]; then
        cp -r "$CLONE_DIR/rules" "$DEST/"
        install_manifest_register "$comp" "$TARGET_PATH/rules/"
      fi
```

- [ ] **Step 2: Syntax check + commit**

```bash
bash -n scripts/install.sh
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for viv-orchestration-rules deploy"
```

---

### Task 8: Wire registration into the viv-hooks case (special)

**Files:**
- Modify: `scripts/install.sh` (the `viv-hooks)` case, around lines 336-356)

- [ ] **Step 1: Locate the case**

This is the special case that deploys both `.claude/hooks/` (the case's `$DEST`) AND `.claude/lib/` (sibling).

- [ ] **Step 2: Register both destinations**

Change:
```bash
      if [ -d "$CLONE_DIR/hooks" ]; then
        for sub in "$CLONE_DIR"/hooks/*; do
          [ -e "$sub" ] || continue
          cp -r "$sub" "$DEST/"
        done
      fi
      if [ -d "$CLONE_DIR/lib" ]; then
        cp -r "$CLONE_DIR/lib" "$TARGET/.claude/"
      fi
      [ -f "$CLONE_DIR/settings.json.fragment" ] && cp "$CLONE_DIR/settings.json.fragment" "$DEST/"
```
to:
```bash
      if [ -d "$CLONE_DIR/hooks" ]; then
        for sub in "$CLONE_DIR"/hooks/*; do
          [ -e "$sub" ] || continue
          cp -r "$sub" "$DEST/"
          install_manifest_register "$comp" "$TARGET_PATH/$(basename "$sub")/"
        done
      fi
      if [ -d "$CLONE_DIR/lib" ]; then
        cp -r "$CLONE_DIR/lib" "$TARGET/.claude/"
        install_manifest_register "$comp" ".claude/lib/"
      fi
      if [ -f "$CLONE_DIR/settings.json.fragment" ]; then
        cp "$CLONE_DIR/settings.json.fragment" "$DEST/"
        install_manifest_register "$comp" "$TARGET_PATH/settings.json.fragment"
      fi
```

Note: `.claude/lib/` is registered with the absolute prefix (not `$TARGET_PATH/lib/`) because for viv-hooks `$TARGET_PATH = .claude/hooks` and the lib path is a sibling, not a child.

- [ ] **Step 3: Syntax check + commit**

```bash
bash -n scripts/install.sh
git add scripts/install.sh
git commit -m "feat(install): register manifest paths for viv-hooks (hooks/, lib/, fragment)"
```

---

### Task 9: Emit manifest at end of install + verify end-to-end

**Files:**
- Modify: `scripts/install.sh` (after the `for comp in $(selected_components)` loop completes, before the "Install complete" banner around line 360)

- [ ] **Step 1: Call install_manifest_emit before the banner**

Find:
```bash
done

echo ""
echo "============================================"
echo "Install complete."
```
Insert between `done` and the blank-line `echo ""`:
```bash
done

if [ "$DRY_RUN" -eq 0 ]; then
  install_manifest_emit
fi

echo ""
echo "============================================"
echo "Install complete."
```

- [ ] **Step 2: Real install against a tmp project, inspect the manifest**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5
test -f "$TMP/.claude/.install-manifest.json" && echo "OK manifest exists" || echo "FAIL"
echo "=== Components in manifest ==="
jq -r '.components | keys[]' "$TMP/.claude/.install-manifest.json"
echo "=== viv-hooks paths (must include .claude/lib/) ==="
jq -r '.components."viv-hooks".paths[]' "$TMP/.claude/.install-manifest.json"
echo "=== viv-skills paths (must list top-level subdirs only, NOT .claude/skills/ itself) ==="
jq -r '.components."viv-skills".paths[]' "$TMP/.claude/.install-manifest.json"
rm -rf "$TMP"
```

Expected:
- `OK manifest exists`
- All 7 components listed (viv-skills, viv-agents, viv-routing, viv-workflows, viv-hooks, viv-orchestration-rules, viv-typed-agents-setup)
- `viv-hooks` paths include `.claude/lib/`
- `viv-skills` paths look like `.claude/skills/backend/`, `.claude/skills/frontend/`, etc. — NOT `.claude/skills/` alone

- [ ] **Step 3: Verify dry-run does NOT write the manifest**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 --dry-run
test ! -f "$TMP/.claude/.install-manifest.json" && echo "OK no manifest in dry-run" || echo "FAIL dry-run wrote manifest"
rm -rf "$TMP"
```
Expected: `OK no manifest in dry-run`.

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat(install): emit .install-manifest.json after deploy completes

Manifest captures, per component, the destination paths just deployed.
Skipped in --dry-run. Required by upcoming uninstall.sh; see
architecture/specs/2026-05-11-uninstall.md."
```

---

### Task 10: Open PR-1

- [ ] **Step 1: Push**

```bash
git push -u origin feat/install-manifest
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --title "feat(install): emit .install-manifest.json on deploy" --body "$(cat <<'EOF'
## Summary

Modify `install.sh` to emit `<target>/.claude/.install-manifest.json` after a successful deploy. The manifest captures, per component, the exact destination paths that were copied (source-side enumeration — robust to re-install).

Required as a foundation for the uninstall flow (see PR-2 and `architecture/specs/2026-05-11-uninstall.md`). Useful on its own for introspection / debugging.

## Manifest format (v1.0)

\`\`\`json
{
  "schema_version": "1.0",
  "installed_at": "2026-05-11T...",
  "tier": 5,
  "components": {
    "viv-skills": {"commit": "2e40a61", "paths": [".claude/skills/backend/", ...]},
    "viv-hooks":  {"commit": "534220e", "paths": [".claude/hooks/deny/", ..., ".claude/lib/"]},
    "viv-typed-agents-setup": {"commit": "<self>", "paths": [".claude/skills/setup/"]}
  }
}
\`\`\`

**Granularity rule:** paths are the top-level subdirs / files the component deployed under its `target_path`, NOT the `target_path` itself. Preserves user customizations in shared namespaces (`.claude/skills/my-team-skill/` stays).

**Special-case capture:** `viv-hooks` deploys to both `.claude/hooks/` and `.claude/lib/` (sibling). Both are registered.

## Test plan

- [x] Fresh \`install.sh --tier 5\` against a tmp dir emits a manifest listing all 7 components with their commit SHAs and per-component path arrays
- [x] \`viv-hooks\` paths include \`.claude/lib/\`
- [x] \`viv-skills\` paths are subdirs (\`.claude/skills/backend/\`) not the parent (\`.claude/skills/\`)
- [x] \`--dry-run\` does NOT write the manifest
EOF
)"
```

- [ ] **Step 3: Wait for merge before starting Phase 2**

After PR-1 merges, sync local main:
```bash
git checkout main
git pull --ff-only
```

---

## Phase 2 — PR-2: Uninstaller

### Task 11: New branch + `unmerge-settings.sh` (TDD)

**Files:**
- Create: `skills/setup/lib/unmerge-settings.sh`
- Modify: `skills/setup/tests/smoke.test.sh` (append assertions)

- [ ] **Step 1: New branch**

```bash
git checkout -b feat/uninstall
```

- [ ] **Step 2: Append failing tests to smoke.test.sh**

Find the final summary `echo` at the bottom of `skills/setup/tests/smoke.test.sh`. Before it, insert:

```bash
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
```

- [ ] **Step 3: Run test, verify it fails**

```bash
cd skills/setup
bash tests/smoke.test.sh
```
Expected: `FAIL: lib/unmerge-settings.sh not found`.

- [ ] **Step 4: Implement `skills/setup/lib/unmerge-settings.sh`**

Create with this exact content:

```bash
#!/usr/bin/env bash
# unmerge-settings.sh <consumer-settings.json> <fragment.json>
# Inverse of merge-settings.sh: remove entries from consumer that match
# fragment. Preserves all other user keys. Idempotent. If the consumer
# becomes top-level {} after unmerge, delete the file.

set -euo pipefail
target="${1:?settings.json path required}"
fragment="${2:?fragment.json path required}"

[ -f "$target" ]   || { echo "target not found: $target" >&2; exit 0; }
[ -f "$fragment" ] || { echo "fragment not found: $fragment" >&2; exit 2; }

tmp=$(mktemp)
jq -n --slurpfile t "$target" --slurpfile f "$fragment" '
  def unmerge_array_aware($a; $b):
    reduce ($b | keys[]) as $k ($a;
      if ($a[$k] | type) == "array" and ($b[$k] | type) == "array"
      then .[$k] = ($a[$k] | map(. as $x | select(($b[$k] | index($x)) == null)))
           | if .[$k] == [] then del(.[$k]) else . end
      elif ($a[$k] | type) == "object" and ($b[$k] | type) == "object"
      then .[$k] = unmerge_array_aware($a[$k]; $b[$k])
           | if .[$k] == {} then del(.[$k]) else . end
      else .
      end);
  unmerge_array_aware($t[0]; $f[0])
' > "$tmp"
mv "$tmp" "$target"

if [ "$(jq -c '.' "$target")" = "{}" ]; then
  rm -f "$target"
fi
```

- [ ] **Step 5: Make executable, run tests**

```bash
chmod +x lib/unmerge-settings.sh
bash tests/smoke.test.sh
```
Expected: 3 new PASS lines (`user keys preserved + fragment entry removed`, `unmerge idempotent`, `empty {} → file removed`).

- [ ] **Step 6: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/unmerge-settings.sh skills/setup/tests/smoke.test.sh
git commit -m "feat(setup): unmerge-settings.sh — reverse of merge-settings, idempotent"
```

---

### Task 12: `unmark-claude-md.sh` (TDD)

**Files:**
- Create: `skills/setup/lib/unmark-claude-md.sh`
- Modify: `skills/setup/tests/smoke.test.sh` (append assertions)

- [ ] **Step 1: Append failing tests**

Before the final summary `echo` in `skills/setup/tests/smoke.test.sh`, append:

```bash
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
```

- [ ] **Step 2: Run, verify fails**

```bash
cd skills/setup && bash tests/smoke.test.sh
```
Expected: `FAIL: lib/unmark-claude-md.sh not found`.

- [ ] **Step 3: Implement `skills/setup/lib/unmark-claude-md.sh`**

Create with this exact content:

```bash
#!/usr/bin/env bash
# unmark-claude-md.sh <claude-md-path> [--remove-if-empty]
# Remove the managed block between <!-- viv-typed-agents:BEGIN --> and
# <!-- viv-typed-agents:END --> (markers inclusive). Preserves all content
# outside the markers. Strips trailing blank lines left by removal.
# Idempotent. With --remove-if-empty, delete the file if it's only
# whitespace after removal.

set -euo pipefail
out="${1:?claude.md path required}"
remove_if_empty=0
[ "${2:-}" = "--remove-if-empty" ] && remove_if_empty=1

[ -f "$out" ] || { echo "not found: $out" >&2; exit 0; }

BEGIN='<!-- viv-typed-agents:BEGIN -->'
END='<!-- viv-typed-agents:END -->'

if ! grep -qF "$BEGIN" "$out"; then
  echo "no managed block in $out — nothing to remove" >&2
  exit 0
fi

tmp=$(mktemp)
awk -v begin="$BEGIN" -v end="$END" '
  BEGIN { in_block = 0 }
  $0 == begin { in_block = 1; next }
  $0 == end   { in_block = 0; next }
  !in_block   { print }
' "$out" > "$tmp"

# Strip trailing whitespace-only lines.
awk 'NR==FNR { lines[NR]=$0; n=NR; next }
     END { 
       last = n
       while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
       for (i = 1; i <= last; i++) print lines[i]
     }' "$tmp" "$tmp" > "$tmp.cleaned"
mv "$tmp.cleaned" "$out"
rm -f "$tmp"

if [ "$remove_if_empty" = "1" ] && [ -z "$(tr -d '[:space:]' < "$out")" ]; then
  rm -f "$out"
fi
```

- [ ] **Step 4: Make executable, run tests**

```bash
chmod +x lib/unmark-claude-md.sh
bash tests/smoke.test.sh
```
Expected: 3 new PASS lines.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/unmark-claude-md.sh skills/setup/tests/smoke.test.sh
git commit -m "feat(setup): unmark-claude-md.sh — remove managed block, idempotent"
```

---

### Task 13: `uninstall.sh` — skeleton (arg parsing + validation)

**Files:**
- Create: `scripts/uninstall.sh`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# scripts/uninstall.sh — Remove a viv-typed-agents installation from a project.
#
# Reads <target>/.claude/.install-manifest.json (written by install.sh) to
# know exactly what to remove. Preserves any content not in the manifest
# (user customizations). Reverses wizard outputs (settings.json,
# CLAUDE.md managed block) ONLY on full uninstall.
#
# Usage:
#   ./uninstall.sh <target-project-path> [options]
#
# Options:
#   --components <list>    CSV of components to remove. Default: all.
#   --dry-run              Print the plan without removing anything.
#   --keep-config          On full uninstall, skip settings.json reverse-merge
#                          and CLAUDE.md unmark.
#   -h | --help            Show this usage.

set -euo pipefail

TARGET=""
COMPONENTS_FILTER=""
DRY_RUN=0
KEEP_CONFIG=0

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --components)  COMPONENTS_FILTER="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --keep-config) KEEP_CONFIG=1; shift ;;
    -h|--help)     usage 0 ;;
    -*)            echo "Unknown flag: $1" >&2; usage 2 ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"; else
        echo "Multiple targets: $TARGET, $1" >&2; usage 2
      fi
      shift
      ;;
  esac
done

[ -z "$TARGET" ] && { echo "Missing <target-project-path>" >&2; usage 2; }
[ -d "$TARGET" ] || { echo "FATAL: target $TARGET is not a directory" >&2; exit 2; }

TARGET="$(cd "$TARGET" && pwd)"
CLAUDE_DIR="$TARGET/.claude"
MANIFEST_PATH="$CLAUDE_DIR/.install-manifest.json"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "No .claude/ directory at $TARGET — nothing to uninstall."
  exit 0
fi

if [ ! -f "$MANIFEST_PATH" ]; then
  cat <<EOF >&2
No install manifest found at $MANIFEST_PATH.

This means viv-typed-agents was installed before manifest support
existed, or the file was deleted. To clean up manually:

  - If you're in git:        git rm -rf .claude/ && git restore CLAUDE.md
  - If not in git:           rm -rf .claude/ then manually revert CLAUDE.md
                             (remove block between viv-typed-agents:BEGIN/END markers)

Aborting.
EOF
  exit 2
fi

# Validate manifest is valid JSON.
if ! jq empty "$MANIFEST_PATH" 2>/dev/null; then
  echo "FATAL: $MANIFEST_PATH is not valid JSON" >&2
  exit 1
fi

echo "============================================"
echo "viv-typed-agents uninstaller"
echo "  target:   $TARGET"
echo "  manifest: $MANIFEST_PATH"
[ "$DRY_RUN" -eq 1 ] && echo "  mode:     DRY RUN (no changes will be made)"
echo "============================================"
echo ""

# (Subsequent tasks fill in resolution + execution.)
echo "(plan-building not yet implemented — TODO Task 14+)"
exit 0
```

- [ ] **Step 2: Make executable, smoke check**

```bash
chmod +x scripts/uninstall.sh
bash -n scripts/uninstall.sh && echo "OK syntax"

# Missing arg
bash scripts/uninstall.sh 2>&1 | head -3
echo "(expected: usage error)"

# Non-existent target
bash scripts/uninstall.sh /nonexistent 2>&1 | head -2

# Real target with no .claude/
TMP=$(mktemp -d)
bash scripts/uninstall.sh "$TMP"
# expected: "No .claude/ directory at $TMP — nothing to uninstall."

# Target with .claude/ but no manifest
mkdir -p "$TMP/.claude"
bash scripts/uninstall.sh "$TMP" 2>&1 | head -10
# expected: "No install manifest found..." block

rm -rf "$TMP"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "feat(uninstall): skeleton — arg parsing, target validation, manifest precheck"
```

---

### Task 14: Load manifest + resolve component selection

**Files:**
- Modify: `scripts/uninstall.sh` (replace the trailing TODO with the resolution logic)

- [ ] **Step 1: Replace the TODO block with manifest loading + filter**

Find:
```bash
# (Subsequent tasks fill in resolution + execution.)
echo "(plan-building not yet implemented — TODO Task 14+)"
exit 0
```

Replace with:

```bash
# Resolve which components to remove.
ALL_COMPONENTS=$(jq -r '.components | keys[]' "$MANIFEST_PATH")
SELECTED_COMPONENTS=""

if [ -n "$COMPONENTS_FILTER" ]; then
  IFS=, read -ra requested <<< "$COMPONENTS_FILTER"
  for req in "${requested[@]}"; do
    req="$(echo "$req" | xargs)"
    if echo "$ALL_COMPONENTS" | grep -qx "$req"; then
      SELECTED_COMPONENTS+="$req"$'\n'
    else
      echo "  ! component '$req' not in install manifest — skipping" >&2
    fi
  done
else
  SELECTED_COMPONENTS="$ALL_COMPONENTS"
fi

SELECTED_COMPONENTS=$(echo "$SELECTED_COMPONENTS" | grep -v '^$' || true)

if [ -z "$SELECTED_COMPONENTS" ]; then
  echo "No components selected for removal."
  exit 0
fi

# (Subsequent tasks fill in plan + execution.)
echo "Selected components:"
echo "$SELECTED_COMPONENTS" | sed 's/^/  - /'
exit 0
```

- [ ] **Step 2: Test**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 >/dev/null 2>&1

# All components
bash scripts/uninstall.sh "$TMP"

# Filtered: known component
bash scripts/uninstall.sh "$TMP" --components viv-hooks

# Filtered: unknown component (warns + skips)
bash scripts/uninstall.sh "$TMP" --components viv-imaginary 2>&1

# Filtered: mix of known + unknown
bash scripts/uninstall.sh "$TMP" --components viv-hooks,viv-imaginary 2>&1

rm -rf "$TMP"
```

Expected: each variant prints the selection it computed; unknown components emit a warning but continue.

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "feat(uninstall): load manifest, resolve component selection"
```

---

### Task 15: Full vs partial detection + plan building

**Files:**
- Modify: `scripts/uninstall.sh` (extend after Task 14's logic)

- [ ] **Step 1: Replace the trailing TODO with detection + plan logic**

Find:
```bash
# (Subsequent tasks fill in plan + execution.)
echo "Selected components:"
echo "$SELECTED_COMPONENTS" | sed 's/^/  - /'
exit 0
```

Replace with:

```bash
# Determine full vs. partial uninstall.
# "Full" = no --components given, OR --components covers every entry in
# the manifest (set equality). The wizard outputs (settings.json
# reverse-merge, CLAUDE.md unmark) only run on full uninstall.
SELECTED_SORTED=$(echo "$SELECTED_COMPONENTS" | sort)
ALL_SORTED=$(echo "$ALL_COMPONENTS" | sort)
if [ "$SELECTED_SORTED" = "$ALL_SORTED" ]; then
  UNINSTALL_MODE="full"
else
  UNINSTALL_MODE="partial"
fi

# Snapshot the settings.json.fragment (used by reverse-merge AFTER directory
# removal would have wiped it). Only relevant for full uninstall.
FRAGMENT_SRC="$CLAUDE_DIR/hooks/settings.json.fragment"
FRAGMENT_SNAPSHOT=""
if [ "$UNINSTALL_MODE" = "full" ] && [ "$KEEP_CONFIG" -eq 0 ] && [ -f "$FRAGMENT_SRC" ]; then
  FRAGMENT_SNAPSHOT=$(mktemp)
  cp "$FRAGMENT_SRC" "$FRAGMENT_SNAPSHOT"
fi

# Build and print the plan.
echo "Uninstall plan ($UNINSTALL_MODE):"
echo ""
echo "  Components and paths to remove:"
while IFS= read -r comp; do
  [ -n "$comp" ] || continue
  jq -r --arg c "$comp" '.components[$c].paths[] | "    ✗ \(.)"' "$MANIFEST_PATH"
done <<< "$SELECTED_COMPONENTS"

if [ "$UNINSTALL_MODE" = "full" ] && [ "$KEEP_CONFIG" -eq 0 ]; then
  echo ""
  echo "  Wizard outputs to reverse:"
  if [ -n "$FRAGMENT_SNAPSHOT" ] && [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo "    ⟲ .claude/settings.json (reverse-merge)"
  fi
  if [ -f "$TARGET/CLAUDE.md" ] && grep -qF "<!-- viv-typed-agents:BEGIN -->" "$TARGET/CLAUDE.md" 2>/dev/null; then
    echo "    ⟲ CLAUDE.md (remove managed block)"
  fi
fi

echo ""
echo "  Transient state to remove (if present):"
echo "    ✗ .claude/.subagent-active.json"
echo "    ✗ .claude/.subagent-active.json.lock"

echo ""
if [ "$UNINSTALL_MODE" = "full" ]; then
  echo "  Manifest:"
  echo "    ✗ .claude/.install-manifest.json (full uninstall)"
else
  echo "  Manifest:"
  echo "    ⟲ .claude/.install-manifest.json (rewrite — remove only selected components)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "Dry-run complete. No changes made."
  [ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
  exit 0
fi

# (Subsequent tasks fill in execution.)
echo ""
echo "(execution not yet implemented — TODO Task 16+)"
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
```

- [ ] **Step 2: Test plan output for full and partial**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 >/dev/null 2>&1

echo "=== Full uninstall plan ==="
bash scripts/uninstall.sh "$TMP" --dry-run

echo ""
echo "=== Partial uninstall plan (viv-hooks only) ==="
bash scripts/uninstall.sh "$TMP" --components viv-hooks --dry-run

rm -rf "$TMP"
```

Expected:
- Full plan lists all components, includes "Wizard outputs to reverse"
- Partial plan lists only viv-hooks, does NOT list wizard outputs (because partial), notes manifest rewrite

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "feat(uninstall): full-vs-partial detection + plan printing + dry-run"
```

---

### Task 16: Execute path removal

**Files:**
- Modify: `scripts/uninstall.sh` (replace the trailing TODO after dry-run)

- [ ] **Step 1: Replace the trailing TODO**

Find:
```bash
# (Subsequent tasks fill in execution.)
echo ""
echo "(execution not yet implemented — TODO Task 16+)"
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
```

Replace with:

```bash
echo ""
echo "Executing..."

# Remove paths from each selected component. Log file vs. directory.
removed_count=0
while IFS= read -r comp; do
  [ -n "$comp" ] || continue
  while IFS= read -r relpath; do
    [ -n "$relpath" ] || continue
    abs="$TARGET/$relpath"
    if [ ! -e "$abs" ]; then
      echo "  ⊘ $relpath (already removed)"
      continue
    fi
    if [ -d "$abs" ]; then
      rm -rf "$abs" || { echo "FATAL: failed to remove directory $abs" >&2; exit 1; }
      echo "  ✗ $relpath (directory)"
    else
      rm -f "$abs" || { echo "FATAL: failed to remove file $abs" >&2; exit 1; }
      echo "  ✗ $relpath (file)"
    fi
    removed_count=$((removed_count + 1))
  done < <(jq -r --arg c "$comp" '.components[$c].paths[]' "$MANIFEST_PATH")
done <<< "$SELECTED_COMPONENTS"

# (Subsequent tasks: reverse-merge, unmark, cleanup, manifest update.)
echo ""
echo "Removed $removed_count paths."
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
```

- [ ] **Step 2: Test removal works**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 >/dev/null 2>&1
ls "$TMP/.claude/" | sort
echo "--- uninstalling viv-hooks ---"
bash scripts/uninstall.sh "$TMP" --components viv-hooks
echo "--- post-uninstall ---"
ls "$TMP/.claude/" | sort
# Expected: .claude/hooks/ and .claude/lib/ gone; other dirs remain.
rm -rf "$TMP"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "feat(uninstall): execute path removal (file/dir distinguished in log)"
```

---

### Task 17: Reverse-merge settings.json + unmark CLAUDE.md (gated)

**Files:**
- Modify: `scripts/uninstall.sh` (replace the trailing exit block after Task 16)

- [ ] **Step 1: Add reverse-merge + unmark before the final exit**

Locate the block:
```bash
# (Subsequent tasks: reverse-merge, unmark, cleanup, manifest update.)
echo ""
echo "Removed $removed_count paths."
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
```

Replace with:

```bash
# Reverse-merge settings.json (FULL uninstall only, --keep-config not set,
# snapshot exists, target settings exists).
if [ "$UNINSTALL_MODE" = "full" ] \
   && [ "$KEEP_CONFIG" -eq 0 ] \
   && [ -n "$FRAGMENT_SNAPSHOT" ] \
   && [ -f "$CLAUDE_DIR/settings.json" ]; then
  # Locate unmerge-settings.sh from the source repo (NOT the target's copy,
  # which we just removed).
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  UNMERGE="$SCRIPT_DIR/../skills/setup/lib/unmerge-settings.sh"
  if [ -x "$UNMERGE" ]; then
    bash "$UNMERGE" "$CLAUDE_DIR/settings.json" "$FRAGMENT_SNAPSHOT"
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
      echo "  ⟲ settings.json reverse-merged (user keys preserved)"
    else
      echo "  ✗ settings.json (became {} after unmerge — removed)"
    fi
  else
    echo "  ! unmerge-settings.sh not found at $UNMERGE — skip settings.json reverse-merge" >&2
  fi
elif [ "$UNINSTALL_MODE" = "full" ] && [ "$KEEP_CONFIG" -eq 0 ] && [ -z "$FRAGMENT_SNAPSHOT" ] && [ -f "$CLAUDE_DIR/settings.json" ]; then
  echo "  ! fragment snapshot missing — review .claude/settings.json manually" >&2
fi

# Unmark CLAUDE.md (FULL uninstall only, --keep-config not set, markers present).
if [ "$UNINSTALL_MODE" = "full" ] \
   && [ "$KEEP_CONFIG" -eq 0 ] \
   && [ -f "$TARGET/CLAUDE.md" ] \
   && grep -qF "<!-- viv-typed-agents:BEGIN -->" "$TARGET/CLAUDE.md"; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  UNMARK="$SCRIPT_DIR/../skills/setup/lib/unmark-claude-md.sh"
  if [ -x "$UNMARK" ]; then
    bash "$UNMARK" "$TARGET/CLAUDE.md"
    echo "  ⟲ CLAUDE.md managed block removed (content outside markers preserved)"
  else
    echo "  ! unmark-claude-md.sh not found at $UNMARK — skip CLAUDE.md unmark" >&2
  fi
fi

# (Subsequent tasks: cleanup transient + empty dirs + manifest update.)
echo ""
echo "Removed $removed_count paths."
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
```

- [ ] **Step 2: Test reverse-merge runs ONLY on full uninstall**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 >/dev/null 2>&1
# Simulate wizard outputs: pretend the user ran /typedAgentSetup
bash "$TMP/.claude/skills/setup/lib/merge-settings.sh" \
     "$TMP/.claude/settings.json" \
     "$TMP/.claude/hooks/settings.json.fragment"
echo '{"theme":"dark"}' > "$TMP/.claude/settings.json.user-keys-only"  # ignore; just verify pre-state
cat > "$TMP/CLAUDE.md" <<'EOF'
# user content
<!-- viv-typed-agents:BEGIN -->
managed
<!-- viv-typed-agents:END -->
EOF

echo "=== Partial uninstall: settings.json should NOT change ==="
prev_settings=$(md5 -q "$TMP/.claude/settings.json" 2>/dev/null || md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)
bash scripts/uninstall.sh "$TMP" --components viv-hooks
test -f "$TMP/.claude/settings.json" && now_settings=$(md5 -q "$TMP/.claude/settings.json" 2>/dev/null || md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)
[ "$prev_settings" = "$now_settings" ] && echo "OK partial: settings unchanged" || echo "FAIL partial touched settings"

echo "=== Full uninstall: settings.json reverse-merged + CLAUDE.md unmarked ==="
# Reset
rm -rf "$TMP"
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 >/dev/null 2>&1
bash "$TMP/.claude/skills/setup/lib/merge-settings.sh" \
     "$TMP/.claude/settings.json" \
     "$TMP/.claude/hooks/settings.json.fragment"
cat > "$TMP/CLAUDE.md" <<'EOF'
# user content
<!-- viv-typed-agents:BEGIN -->
managed
<!-- viv-typed-agents:END -->
EOF
bash scripts/uninstall.sh "$TMP"
grep -qF "# user content" "$TMP/CLAUDE.md" && ! grep -qF "managed" "$TMP/CLAUDE.md" && echo "OK full: CLAUDE.md unmarked" || echo "FAIL full unmark"

rm -rf "$TMP"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "feat(uninstall): reverse-merge settings.json + unmark CLAUDE.md (full only)"
```

---

### Task 18: Cleanup transient + empty dirs + manifest update

**Files:**
- Modify: `scripts/uninstall.sh` (replace the final exit block)

- [ ] **Step 1: Replace the trailing block**

Locate:
```bash
# (Subsequent tasks: cleanup transient + empty dirs + manifest update.)
echo ""
echo "Removed $removed_count paths."
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
```

Replace with:

```bash
# Cleanup transient state (subagent marker registry).
for f in "$CLAUDE_DIR/.subagent-active.json" "$CLAUDE_DIR/.subagent-active.json.lock"; do
  if [ -f "$f" ]; then
    rm -f "$f"
    echo "  ✗ $(echo "$f" | sed "s|^$TARGET/||")"
  fi
done

# Update or remove manifest.
if [ "$UNINSTALL_MODE" = "full" ]; then
  rm -f "$MANIFEST_PATH"
  echo "  ✗ .claude/.install-manifest.json"
else
  # Rewrite manifest with remaining components.
  tmp=$(mktemp)
  jq --argjson removed "$(echo "$SELECTED_COMPONENTS" | jq -R . | jq -s .)" \
     '.components = (.components | with_entries(select(.key as $k | $removed | index($k) | not)))' \
     "$MANIFEST_PATH" > "$tmp"
  mv "$tmp" "$MANIFEST_PATH"
  echo "  ⟲ .claude/.install-manifest.json (updated; removed components excluded)"
fi

# Bottom-up empty-dir cleanup.
find "$CLAUDE_DIR" -depth -type d -empty -delete 2>/dev/null || true

# If .claude/ was removed entirely:
if [ ! -d "$CLAUDE_DIR" ]; then
  echo "  ✗ .claude/ (now empty — removed)"
fi

# Free the fragment snapshot.
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"

echo ""
echo "============================================"
echo "Uninstall complete."
echo "  - $removed_count component paths removed"
echo "  - mode: $UNINSTALL_MODE"
[ "$UNINSTALL_MODE" = "full" ] && [ "$KEEP_CONFIG" -eq 0 ] && echo "  - wizard outputs reverted"
echo ""
echo "Review with: git status"
echo "============================================"
```

- [ ] **Step 2: Test end-to-end against a fresh install**

```bash
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 >/dev/null 2>&1
echo "=== Pre-uninstall .claude/ structure ==="
find "$TMP/.claude" -maxdepth 2 -type d | sort
echo ""
bash scripts/uninstall.sh "$TMP"
echo ""
echo "=== Post-uninstall ==="
ls "$TMP" 2>&1
test ! -d "$TMP/.claude" && echo "OK .claude/ fully removed" || (echo "FAIL — remaining:"; ls "$TMP/.claude/")
rm -rf "$TMP"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "feat(uninstall): transient state cleanup + manifest update + empty-dir collapse"
```

---

### Task 19: E2E round-trip test (full uninstall)

**Files:**
- Create: `skills/setup/tests/uninstall.test.sh`

- [ ] **Step 1: Write the test**

```bash
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
jq -e '.components."viv-hooks".paths | index(".claude/lib/")' "$TMP/.claude/.install-manifest.json" >/dev/null \
  && ok "viv-hooks manifest includes .claude/lib/" || ko "missing .claude/lib/"

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
[ ! -d "$TMP/.claude/lib" ]    && ok ".claude/lib/ removed (viv-hooks sibling)" || ko ".claude/lib/ remains"
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
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Make executable, run**

```bash
chmod +x skills/setup/tests/uninstall.test.sh
bash skills/setup/tests/uninstall.test.sh
echo "EXIT=$?"
```
Expected: all PASS, EXIT=0.

- [ ] **Step 3: Commit**

```bash
git add skills/setup/tests/uninstall.test.sh
git commit -m "test(uninstall): e2e round-trip — install + wizard + full uninstall"
```

---

### Task 20: Partial-uninstall test case

**Files:**
- Modify: `skills/setup/tests/uninstall.test.sh` (add a partial-uninstall section)

- [ ] **Step 1: Append the partial case**

Before the final `Result:` summary, append:

```bash
echo ""
echo "--- Partial uninstall (--components viv-hooks) ---"
# Reset target.
rm -rf "$TMP"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT  # re-arm

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

# viv-hooks should be gone.
[ ! -d "$TMP/.claude/hooks" ] && ok "partial: viv-hooks removed" || ko "viv-hooks remains"
[ ! -d "$TMP/.claude/lib" ]   && ok "partial: .claude/lib/ removed" || ko ".claude/lib/ remains"

# OTHER components should remain.
[ -d "$TMP/.claude/agents" ]        && ok "partial: viv-agents preserved" || ko "agents removed unexpectedly"
[ -d "$TMP/.claude/orchestration" ] && ok "partial: orchestration preserved" || ko "orchestration removed unexpectedly"

# Wizard outputs MUST be untouched (the spec invariant).
settings_after=$(md5 -q "$TMP/.claude/settings.json" 2>/dev/null || md5sum "$TMP/.claude/settings.json" | cut -d' ' -f1)
claudemd_after=$(md5 -q "$TMP/CLAUDE.md" 2>/dev/null || md5sum "$TMP/CLAUDE.md" | cut -d' ' -f1)
[ "$settings_before" = "$settings_after" ] && ok "partial: settings.json untouched" || ko "settings.json modified by partial"
[ "$claudemd_before" = "$claudemd_after" ] && ok "partial: CLAUDE.md untouched"   || ko "CLAUDE.md modified by partial"

# Manifest should be REWRITTEN (without viv-hooks).
jq -e '.components | has("viv-hooks") | not' "$TMP/.claude/.install-manifest.json" >/dev/null \
  && ok "partial: manifest rewritten without viv-hooks" || ko "manifest still lists viv-hooks"
jq -e '.components | has("viv-agents")' "$TMP/.claude/.install-manifest.json" >/dev/null \
  && ok "partial: manifest preserves viv-agents" || ko "manifest dropped viv-agents"
```

- [ ] **Step 2: Run**

```bash
bash skills/setup/tests/uninstall.test.sh
```
Expected: all original PASSes plus the partial-uninstall PASSes (~7 new).

- [ ] **Step 3: Commit**

```bash
git add skills/setup/tests/uninstall.test.sh
git commit -m "test(uninstall): partial uninstall preserves wizard outputs"
```

---

### Task 21: Update README with uninstall section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Locate the install section**

```bash
grep -n "^## " README.md
```

- [ ] **Step 2: Insert a new section after Install (and after the "After install — run the setup wizard" section)**

Add this section to `README.md` (place it between the wizard section and "What you get post-install"):

```markdown
## Uninstall

To remove a viv-typed-agents installation from a consumer project:

\`\`\`bash
./scripts/uninstall.sh /path/to/your-project
\`\`\`

Defaults: removes all components, reverses the wizard's modifications to `settings.json` and `CLAUDE.md`, cleans up transient state, and removes `.claude/.install-manifest.json`. User customizations under shared namespaces (e.g., `.claude/skills/my-team-skill/`) are preserved.

### Options

| Flag | Behavior |
|---|---|
| `--components <list>` | CSV of components to remove. Default: all. Partial uninstall does NOT touch `settings.json` or `CLAUDE.md`. |
| `--dry-run` | Print the plan without removing anything. |
| `--keep-config` | On full uninstall, skip `settings.json` reverse-merge and `CLAUDE.md` unmark. |

### Examples

\`\`\`bash
# Preview what would happen
./scripts/uninstall.sh ~/my-project --dry-run

# Downgrade: keep tier 3 (skills + agents + routing + workflows + orchestration),
# remove only the hooks layer
./scripts/uninstall.sh ~/my-project --components viv-hooks

# Full uninstall but keep your manually-edited settings.json + CLAUDE.md
./scripts/uninstall.sh ~/my-project --keep-config
\`\`\`

The uninstaller reads `<target>/.claude/.install-manifest.json` (written by `install.sh`) to know exactly which paths it deployed. If the manifest is missing (e.g., the install pre-dates manifest support), the uninstaller aborts and points you to manual cleanup. See `architecture/specs/2026-05-11-uninstall.md` for the full design.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document uninstall.sh"
```

---

### Task 22: Open PR-2

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/uninstall
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --title "feat: uninstall flow (uninstall.sh + 2 lib scripts + e2e tests)" --body "$(cat <<'EOF'
## Summary

Adds a turnkey uninstaller for viv-typed-agents installations. Depends on the install manifest emitted by PR #X (must merge first).

**New files:**
- \`scripts/uninstall.sh\` — orchestrator
- \`skills/setup/lib/unmerge-settings.sh\` — reverse of merge-settings (idempotent)
- \`skills/setup/lib/unmark-claude-md.sh\` — removes managed block between viv-typed-agents:BEGIN/END markers
- \`skills/setup/tests/uninstall.test.sh\` — e2e round-trip test

**Key design decisions (from spec):**
- Source-side manifest: install captures destination paths it owns; uninstall removes exactly those. User customizations in shared namespaces survive.
- Wizard outputs (\`settings.json\` reverse-merge, \`CLAUDE.md\` unmark) only run on **full** uninstall. Partial uninstall (via \`--components\`) leaves them alone — preventing inconsistent state.
- No \`--legacy\`, no backup, no \`--force\`, no \`--tier\` flag — these would re-introduce risks the design specifically rejects (see spec "What is intentionally NOT done").
- Order of operations: fragment snapshotted BEFORE removal so the reverse-merge still has its source.

## Test plan

- [x] \`bash skills/setup/tests/smoke.test.sh\` — 28+ → 34+ pass, 0 fail (new \`unmerge-settings\` + \`unmark-claude-md\` assertions)
- [x] \`bash skills/setup/tests/uninstall.test.sh\` — full + partial round-trip both PASS
- [x] Full uninstall against a tmp consumer with planted user customizations: user content survives, typed-agents content gone, manifest removed
- [x] Partial uninstall (\`--components viv-hooks\`): hooks gone, other components untouched, settings.json and CLAUDE.md byte-identical to pre-uninstall
- [x] \`--dry-run\` prints the plan without modifying the filesystem

## Reference

Spec: \`architecture/specs/2026-05-11-uninstall.md\`
EOF
)"
```

---

## Self-review checklist (run after all tasks)

- [ ] All spec sections have at least one task implementing them:
  - Problem/Goal → Tasks 11-22 (the whole uninstall flow)
  - Manifest format → Tasks 1-9
  - Granularity rule → Task 3-8 (per-case source-side registration)
  - Algorithm steps 0-10 → Tasks 13-18
  - Lib scripts → Tasks 11-12
  - Error handling → Task 13 (validation) + Task 14 (unknown component) + Task 17 (snapshot missing) + Task 18 (manifest rewrite)
  - Testing → Tasks 19-20
  - "What is intentionally NOT done" → Implicit (no flags added for those)
- [ ] No `TBD` / `TODO` / `placeholder` / "implement later" strings in this plan
- [ ] All lib scripts have a contract documented at top + tests before implementation (TDD)
- [ ] All commits are small (one capability per commit)
- [ ] Marker strings (`<!-- viv-typed-agents:BEGIN -->` and `<!-- viv-typed-agents:END -->`) consistent across spec, lib scripts, tests
- [ ] Manifest schema field names (`schema_version`, `installed_at`, `tier`, `components`, `commit`, `paths`) consistent across install.sh emit, uninstall.sh read, e2e test
