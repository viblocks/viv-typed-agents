#!/usr/bin/env bash
# scripts/install.sh — Deploy the typed-agents product to a consumer project.
#
# Per ADR-RD-010, viv-typed-agents is the installable product composed of
# 6 internal components pinned in MANIFEST.yaml. This script clones each
# component at its pinned SHA and copies its content to the target project's
# .claude/ directory.
#
# Usage:
#   ./install.sh <target-project-path> [options]
#
# Options:
#   --tier N                 Tier (1..5). Default: 5. Determines default component set.
#   --skills <list>          Override: only install named skills (comma-separated).
#                            Skill names are folder basenames under viv-skills/<area>/.
#   --agents <list>          Override: only install named agents.
#   --components <list>      Override: only install named components (comma-separated).
#   --exclude <list>         Skip named components even if tier includes them.
#   --dry-run                Print actions without executing.
#   --keep-vendor            Keep the .vendor/ working dir (for inspection).
#
# Examples:
#   ./install.sh ~/my-project --tier 5
#   ./install.sh ~/my-project --tier 1
#   ./install.sh ~/my-project --skills crypto-backend,nestjs-backend
#   ./install.sh ~/my-project --tier 4 --exclude viv-orchestration-rules
#
# Requirements: bash, git, yq, awk, sed.

set -euo pipefail

# ---------- arg parsing ----------
TARGET=""
TIER=5
SKILLS_FILTER=""
AGENTS_FILTER=""
COMPONENTS_FILTER=""
EXCLUDE_LIST=""
DRY_RUN=0
KEEP_VENDOR=0

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier)             TIER="$2"; shift 2 ;;
    --skills)           SKILLS_FILTER="$2"; shift 2 ;;
    --agents)           AGENTS_FILTER="$2"; shift 2 ;;
    --components)       COMPONENTS_FILTER="$2"; shift 2 ;;
    --exclude)          EXCLUDE_LIST="$2"; shift 2 ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --keep-vendor)      KEEP_VENDOR=1; shift ;;
    -h|--help)          usage 0 ;;
    -*)                 echo "Unknown flag: $1" >&2; usage 2 ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"; else
        echo "Multiple targets: $TARGET, $1" >&2; usage 2
      fi
      shift
      ;;
  esac
done

[ -z "$TARGET" ] && { echo "Missing <target-project-path>" >&2; usage 2; }

# Resolve target absolute path.
TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")" || {
  echo "FATAL: cannot resolve target $TARGET" >&2; exit 2;
}
[ ! -d "$TARGET" ] && { echo "FATAL: target $TARGET does not exist" >&2; exit 2; }

# ---------- locate manifest ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/MANIFEST.yaml"
[ -f "$MANIFEST" ] || { echo "FATAL: MANIFEST.yaml not found at $MANIFEST" >&2; exit 2; }

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
    local sha; sha=$(yq_get ".components.\"$c\".commit")
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

# ---------- runtime deps ----------
for dep in git awk sed; do
  command -v "$dep" >/dev/null 2>&1 || { echo "FATAL: $dep required" >&2; exit 2; }
done

# YAML reader: prefer yq; fallback to python3+yaml.
YAML_READER=""
if command -v yq >/dev/null 2>&1; then
  YAML_READER="yq"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  YAML_READER="python"
else
  echo "FATAL: need either yq OR python3 with PyYAML to parse MANIFEST.yaml" >&2
  echo "       brew install yq    # or:    pip3 install pyyaml" >&2
  exit 2
fi

# yq_get <yq-expr> — read from MANIFEST. Works whether YAML_READER is yq or python.
# yq expressions and jq expressions overlap for simple cases (.components, |, keys[]).
yq_get() {
  local expr="$1"
  if [ "$YAML_READER" = "yq" ]; then
    yq "$expr" "$MANIFEST"
  else
    # Convert YAML to JSON via python, then run jq.
    python3 -c 'import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$MANIFEST" | jq -r "$expr"
  fi
}

# ---------- helpers ----------
in_csv() {
  # in_csv <needle> <haystack-csv>  → 0 if needle in haystack
  local needle="$1" hay="$2" item
  IFS=, read -ra arr <<< "$hay"
  for item in "${arr[@]}"; do
    [ "$(echo "$item" | xargs)" = "$needle" ] && return 0
  done
  return 1
}

manifest_components() {
  yq_get '.components | keys[]'
}

component_field() {
  local comp="$1" field="$2"
  yq_get ".components.\"$comp\".$field"
}

component_tiers() {
  local comp="$1"
  yq_get ".components.\"$comp\".tiers[]"
}

# ---------- selection logic ----------
selected_components() {
  local comp tiers t included
  for comp in $(manifest_components); do
    # Component-level filters first.
    [ -n "$COMPONENTS_FILTER" ] && ! in_csv "$comp" "$COMPONENTS_FILTER" && continue
    [ -n "$EXCLUDE_LIST" ] && in_csv "$comp" "$EXCLUDE_LIST" && continue

    # Tier filter.
    included=0
    for t in $(component_tiers "$comp"); do
      if [ "$t" -le "$TIER" ]; then included=1; break; fi
    done
    [ "$included" -eq 1 ] && echo "$comp"
  done
}

# ---------- main ----------
echo "============================================"
echo "viv-typed-agents installer"
echo "  target: $TARGET"
echo "  tier:   $TIER"
[ -n "$COMPONENTS_FILTER" ] && echo "  components filter: $COMPONENTS_FILTER"
[ -n "$EXCLUDE_LIST" ]      && echo "  exclude:           $EXCLUDE_LIST"
[ -n "$SKILLS_FILTER" ]     && echo "  skills filter:     $SKILLS_FILTER"
[ -n "$AGENTS_FILTER" ]     && echo "  agents filter:     $AGENTS_FILTER"
[ "$DRY_RUN" -eq 1 ]        && echo "  DRY RUN — no changes will be made"
echo "============================================"

VENDOR_DIR="$REPO_ROOT/.vendor"
mkdir -p "$VENDOR_DIR"

cleanup_vendor() {
  if [ "$KEEP_VENDOR" -eq 0 ] && [ -d "$VENDOR_DIR" ]; then
    rm -rf "$VENDOR_DIR"
  fi
}
trap cleanup_vendor EXIT

# ---------- per-component install ----------
for comp in $(selected_components); do
  REPO_URL=$(component_field "$comp" repo)
  if [ "$REPO_URL" = "<self>" ]; then
    # Component lives in this repo — copy directly from source_path to target_path.
    SELF_SRC_REL=$(component_field "$comp" source_path)
    SELF_TARGET_REL=$(component_field "$comp" target_path)
    SELF_ROLE=$(component_field "$comp" role)
    SELF_SRC="$REPO_ROOT/$SELF_SRC_REL"

    echo ""
    echo ">>> $comp (<self>) — $SELF_ROLE"
    echo "    deploy → $TARGET/$SELF_TARGET_REL"

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "    (dry-run; skipping)"
      continue
    fi

    if [ ! -d "$SELF_SRC" ]; then
      echo "  ✗ $comp source_path does not exist: $SELF_SRC" >&2
      exit 1
    fi
    mkdir -p "$TARGET/$SELF_TARGET_REL"
    cp -R "$SELF_SRC/." "$TARGET/$SELF_TARGET_REL/"
    find "$TARGET/$SELF_TARGET_REL" -name '*.sh' -type f -exec chmod +x {} \; 2>/dev/null || true
    install_manifest_register "$comp" "$SELF_TARGET_REL"
    echo "    ✓ copied from $SELF_SRC"
    continue
  fi
  COMMIT=$(component_field "$comp" commit)
  TARGET_PATH=$(component_field "$comp" target_path)
  ROLE=$(component_field "$comp" role)

  echo ""
  echo ">>> $comp ($COMMIT) — $ROLE"
  echo "    deploy → $TARGET/$TARGET_PATH"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    (dry-run; skipping)"
    continue
  fi

  # Clone or fetch.
  CLONE_DIR="$VENDOR_DIR/$comp"
  if [ ! -d "$CLONE_DIR/.git" ]; then
    git clone --quiet --depth 50 "$REPO_URL" "$CLONE_DIR"
  fi
  git -C "$CLONE_DIR" fetch --quiet --depth 50 origin "$COMMIT" 2>/dev/null || \
    git -C "$CLONE_DIR" fetch --quiet origin
  git -C "$CLONE_DIR" checkout --quiet "$COMMIT"

  # Prepare destination.
  DEST="$TARGET/$TARGET_PATH"
  mkdir -p "$DEST"

  # Per-component deploy logic. Each case is responsible for placing files
  # at paths the runtime loaders (routing-loader, workflow-loader, hooks)
  # actually look for — NOT for replicating the upstream repo layout.
  case "$comp" in
    viv-skills)
      # Skill areas live as top-level dirs in viv-skills (backend/, frontend/, devops/, etc.)
      # Skip repo metadata: .git, architecture, logs, docs, CLAUDE.md, README.md, .gitignore.
      if [ -n "$SKILLS_FILTER" ]; then
        IFS=, read -ra skills <<< "$SKILLS_FILTER"
        for skill in "${skills[@]}"; do
          skill="$(echo "$skill" | xargs)"
          found=$(find "$CLONE_DIR" -maxdepth 3 -type d -name "$skill" -not -path "*/.git/*" | head -1)
          if [ -n "$found" ]; then
            cp -r "$found" "$DEST/"
            install_manifest_register "$comp" "$TARGET_PATH/$skill/"
            echo "    + skill: $skill"
          else
            echo "    ! skill not found: $skill" >&2
          fi
        done
      else
        for sub in "$CLONE_DIR"/*; do
          name=$(basename "$sub")
          case "$name" in
            .git|architecture|logs|docs|CLAUDE.md|README.md|.gitignore|.gitattributes|LICENSE) continue ;;
            *)
              if [ -d "$sub" ]; then
                cp -r "$sub" "$DEST/"
                install_manifest_register "$comp" "$TARGET_PATH/$name/"
              fi
              ;;
          esac
        done
      fi
      ;;
    viv-agents)
      # Agents live under domain subfolders: backend/, frontend/, devops/, security/, testing/.
      # Each subfolder contains <agent-name>.md files. Skip _shared/ (helpers),
      # architecture/ (repo metadata), and repo README.md.
      if [ -n "$AGENTS_FILTER" ]; then
        IFS=, read -ra agents <<< "$AGENTS_FILTER"
        for agent in "${agents[@]}"; do
          agent="$(echo "$agent" | xargs)"
          # Search in domain subfolders.
          found=$(find "$CLONE_DIR" -maxdepth 3 -name "${agent}.md" -type f \
                  -not -path "*/.git/*" \
                  -not -path "*/_shared/*" \
                  -not -path "*/architecture/*" | head -1)
          if [ -n "$found" ]; then
            cp "$found" "$DEST/"
            install_manifest_register "$comp" "$TARGET_PATH/${agent}.md"
            echo "    + agent: $agent"
          else
            echo "    ! agent not found: $agent" >&2
          fi
        done
      else
        # All .md files inside domain subfolders. Skip _shared/, architecture/, repo README.
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
        # Drop any top-level README that snuck in (find -not -path with $CLONE_DIR/README.md
        # only excludes the literal path; find-rel may still match).
        rm -f "$DEST/README.md" "$DEST/CLAUDE.md" 2>/dev/null || true
      fi
      ;;
    viv-routing)
      # Deploy a usable routing-table.json (from the full-stack example, which has
      # the redesigned classifier-folded structure) plus the schema. Consumer can
      # edit routing-table.json to fit their project paths/agents.
      if [ -f "$CLONE_DIR/examples/full-stack.routing-table.json" ]; then
        cp "$CLONE_DIR/examples/full-stack.routing-table.json" "$DEST/routing-table.json"
        # Fix the relative $schema reference for the new location.
        sed -i.bak 's|"\$schema": "../schema/|"$schema": "./schema/|' "$DEST/routing-table.json"
        rm -f "$DEST/routing-table.json.bak"
      elif [ -f "$CLONE_DIR/routing-table.template.json" ]; then
        cp "$CLONE_DIR/routing-table.template.json" "$DEST/routing-table.json"
      fi
      [ -d "$CLONE_DIR/schema" ] && cp -r "$CLONE_DIR/schema" "$DEST/"
      [ -f "$CLONE_DIR/NAMING.md" ] && cp "$CLONE_DIR/NAMING.md" "$DEST/"
      ;;
    viv-workflows)
      # Flatten rules/<name>.template.json → workflows/<name>.json (the path
      # workflow-loader expects). Schemas kept under schemas/ for validation.
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
      # Also preserve the viblocks-style examples for reference (optional).
      if [ -d "$CLONE_DIR/examples/viblocks-style" ]; then
        mkdir -p "$DEST/examples/viblocks-style"
        cp -r "$CLONE_DIR"/examples/viblocks-style/* "$DEST/examples/viblocks-style/"
      fi
      ;;
    viv-orchestration-rules)
      # CLAUDE.template.md at root + playbooks/ at root. Skip repo metadata.
      [ -f "$CLONE_DIR/CLAUDE.template.md" ] && cp "$CLONE_DIR/CLAUDE.template.md" "$DEST/"
      [ -d "$CLONE_DIR/playbooks" ] && cp -r "$CLONE_DIR/playbooks" "$DEST/"
      ;;
    viv-hooks)
      # Flatten hooks/<type>/* directly under DEST so paths are .claude/hooks/<type>/...
      # NOT .claude/hooks/hooks/<type>/...
      if [ -d "$CLONE_DIR/hooks" ]; then
        for sub in "$CLONE_DIR"/hooks/*; do
          [ -e "$sub" ] || continue
          cp -r "$sub" "$DEST/"
        done
      fi
      # IMPORTANT: lib/ goes to .claude/lib/ (sibling of hooks/) — NOT inside hooks/.
      # The hook scripts resolve $LIB_DIR as $HOOK_DIR/../../lib which from
      # .claude/hooks/<type>/<hook>.sh evaluates to .claude/lib (matching the
      # upstream layout where lib is sibling of hooks/).
      if [ -d "$CLONE_DIR/lib" ]; then
        cp -r "$CLONE_DIR/lib" "$TARGET/.claude/"
      fi
      [ -f "$CLONE_DIR/settings.json.fragment" ] && cp "$CLONE_DIR/settings.json.fragment" "$DEST/"
      # Make hook scripts executable.
      find "$DEST" -name '*.sh' -type f -exec chmod +x {} \; 2>/dev/null || true
      find "$TARGET/.claude/lib" -name '*.sh' -type f -exec chmod +x {} \; 2>/dev/null || true
      ;;
  esac
done

echo ""
echo "============================================"
echo "Install complete."
echo "Next steps:"
echo "  1. Configure routing: edit $TARGET/.claude/routing/routing-table.json"
echo "  2. Configure workflows: review $TARGET/.claude/workflows/"
echo "  3. (Tier 4+) Glue settings: merge $TARGET/.claude/hooks/settings.json.fragment into $TARGET/.claude/settings.json"
echo "  4. (Tier 5)  Adapt CLAUDE.md from $TARGET/.claude/orchestration/CLAUDE.template.md"
echo "============================================"
