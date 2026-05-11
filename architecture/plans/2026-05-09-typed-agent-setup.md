# `/typedAgentSetup` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an interactive `/typedAgentSetup` skill that completes post-install configuration of viv-typed-agents in a consumer project (routing-table, settings.json merge, CLAUDE.md adaptation), so the consumer is ready to use typed agents after one command.

**Architecture:** A skill living in `viv-typed-agents/skills/setup/` with a SKILL.md prompt that orchestrates a 5-phase wizard, delegating deterministic work to bash scripts in `lib/`. Two prerequisite migrations: `viv-agents` adds a `business_domain` frontmatter field; `viv-skills` adds `detection` signatures to stack-introducing skills.

**Tech Stack:** Bash (lib scripts, smoke tests), Markdown (SKILL.md, frontmatter), `jq` (JSON manipulation), `yq` (YAML manipulation, already a dependency of `install.sh`).

**Repos touched (in order):**
1. `/Users/viv/AI/vault/viv-agents` — migration 1
2. `/Users/viv/AI/vault/viv-skills` — migration 2
3. `/Users/viv/AI/vault/viv-typed-agents` — the skill + MANIFEST update

**Reference spec:** `architecture/specs/2026-05-09-typed-agent-setup.md`

---

## Phase 1 — Prerequisite migrations

### Task 1: Add `business_domain` field to all agents in viv-agents

**Repo:** `/Users/viv/AI/vault/viv-agents`

**Files:**
- Modify: `backend/backend-implementer.md`, `backend/backend-reviewer.md` → `business_domain: generic`
- Modify: `backend/backend-crypto-implementer.md`, `backend/backend-crypto-reviewer.md` → `business_domain: crypto`
- Modify: `backend/backend-waas-implementer.md`, `backend/backend-waas-reviewer.md` → `business_domain: waas`
- Modify: `frontend/frontend-implementer.md`, `frontend/frontend-reviewer.md` → `business_domain: generic`
- Modify: `frontend/frontend-crypto-implementer.md`, `frontend/frontend-crypto-reviewer.md` → `business_domain: crypto`
- Modify: `frontend/frontend-waas-implementer.md`, `frontend/frontend-waas-reviewer.md` → `business_domain: waas`
- Modify: `devops/infra-devops-implementer.md`, `devops/infra-devops-reviewer.md` → `business_domain: cross-cutting`
- Modify: `security/security-reviewer.md`, `testing/dev-testing-strategy-reviewer.md` → `business_domain: cross-cutting`

- [ ] **Step 1: Add `business_domain` to one specialized agent first (smoke test)**

Edit `backend/backend-crypto-implementer.md`. Insert immediately after the `domain:` line:

```yaml
business_domain: crypto
```

Final frontmatter top should read:
```yaml
---
name: backend-crypto-implementer
type: implementer
domain: backend
business_domain: crypto
description: >
  ...
```

- [ ] **Step 2: Verify YAML is still valid**

```bash
cd /Users/viv/AI/vault/viv-agents
python3 -c "
import yaml, sys
with open('backend/backend-crypto-implementer.md') as f:
    content = f.read()
parts = content.split('---', 2)
fm = yaml.safe_load(parts[1])
assert fm['business_domain'] == 'crypto', fm
print('OK')
"
```
Expected: `OK`

- [ ] **Step 3: Apply the same edit to the remaining 13 files**

Edit each file in the Files list above, inserting `business_domain: <value>` immediately after the `domain:` line. Use the value mapped per file in the Files list.

- [ ] **Step 4: Validate all frontmatter is well-formed and has the field**

```bash
cd /Users/viv/AI/vault/viv-agents
python3 -c "
import yaml, glob, sys
missing = []
for f in sorted(glob.glob('*/*-implementer.md') + glob.glob('*/*-reviewer.md')):
    with open(f) as fh: content = fh.read()
    parts = content.split('---', 2)
    if len(parts) < 3: missing.append(f + ' (no frontmatter)'); continue
    fm = yaml.safe_load(parts[1])
    if 'business_domain' not in fm: missing.append(f + ' (no business_domain)')
    else: print(f, '->', fm['business_domain'])
sys.exit(1 if missing else 0)
" || (echo 'FAIL'; exit 1)
```
Expected: 14 lines printed, each ending with `crypto`/`waas`/`generic`/`cross-cutting`. Exit 0.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-agents
git add backend/ frontend/ devops/ security/ testing/
git commit -m "feat: add business_domain frontmatter field to all agents

Enables /typedAgentSetup to discover available business domains by
scanning installed agents. See viv-typed-agents/architecture/specs/
2026-05-09-typed-agent-setup.md (Migration 1)."
```

---

### Task 2: Add `detection` signatures to stack-introducing skills in viv-skills

**Repo:** `/Users/viv/AI/vault/viv-skills`

Only skills that introduce a stack (not domain knowledge) get the field. From inspection: `nestjs-backend` and `react-frontend`. Domain skills (`crypto-backend`, `waas-backend`, `react-crypto-frontend`, `waas-frontend`, etc.) do not.

**Files:**
- Modify: `backend/nestjs-backend/SKILL.md`
- Modify: `frontend/react-frontend/SKILL.md`

- [ ] **Step 1: Add `detection` block to `nestjs-backend/SKILL.md`**

Insert into the frontmatter, before the closing `---`:

```yaml
detection:
  layer: backend
  entry_files:
    - main.ts
    - nest-cli.json
  file_globs:
    - "src/**/*.module.ts"
```

- [ ] **Step 2: Add `detection` block to `react-frontend/SKILL.md`**

Insert into the frontmatter, before the closing `---`:

```yaml
detection:
  layer: frontend
  config_files:
    - vite.config.ts
    - vite.config.js
    - next.config.ts
    - next.config.js
  file_globs:
    - "**/*.tsx"
    - "**/*.jsx"
```

- [ ] **Step 3: Validate both YAMLs**

```bash
cd /Users/viv/AI/vault/viv-skills
for f in backend/nestjs-backend/SKILL.md frontend/react-frontend/SKILL.md; do
  python3 -c "
import yaml
with open('$f') as fh: content = fh.read()
fm = yaml.safe_load(content.split('---', 2)[1])
assert 'detection' in fm, '$f missing detection'
assert fm['detection']['layer'] in ('backend','frontend')
print('$f OK ->', fm['detection']['layer'])
"
done
```
Expected: two `OK` lines.

- [ ] **Step 4: Commit**

```bash
cd /Users/viv/AI/vault/viv-skills
git add backend/nestjs-backend/SKILL.md frontend/react-frontend/SKILL.md
git commit -m "feat: add detection frontmatter to stack-introducing skills

Allows /typedAgentSetup to classify service folders by reading
detection signatures from installed skills. Only nestjs-backend and
react-frontend (current stacks) get the field. Domain skills are
unchanged. See viv-typed-agents/architecture/specs/2026-05-09-typed
-agent-setup.md (Migration 2)."
```

---

## Phase 2 — Skill foundation

### Task 3: Scaffold skill directory and MANIFEST entry

**Repo:** `/Users/viv/AI/vault/viv-typed-agents`

**Files:**
- Create: `skills/setup/SKILL.md` (frontmatter stub only)
- Create: `skills/setup/lib/.gitkeep`
- Create: `skills/setup/tests/.gitkeep`
- Create: `skills/setup/tests/fixtures/.gitkeep`
- Modify: `MANIFEST.yaml` (add `skills/setup/` to typed-agents own deliverables)

- [ ] **Step 1: Create skill directory tree**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
mkdir -p skills/setup/lib skills/setup/tests/fixtures
touch skills/setup/lib/.gitkeep skills/setup/tests/fixtures/.gitkeep
```

- [ ] **Step 2: Write SKILL.md frontmatter stub**

Create `skills/setup/SKILL.md`:

```markdown
---
name: typedAgentSetup
description: >
  Use after running viv-typed-agents/scripts/install.sh on a consumer project.
  Configures the routing-table, merges hook settings, and adapts the CLAUDE.md
  template based on the project's structure and selected business domain.
  Activated via /typedAgentSetup.
tier_required: 3
---

# /typedAgentSetup — Wizard for completing typed-agents post-install configuration

(Body written in Task 13.)
```

- [ ] **Step 3: Add setup skill to MANIFEST.yaml**

Add this entry to `MANIFEST.yaml`'s `components:` block (alphabetical with existing entries):

```yaml
  viv-typed-agents-setup:
    repo: <self>
    commit: <self>
    role: post-install configuration wizard (skill). Lives in this product repo (not a separate component).
    target_path: .claude/skills/setup/
    tiers: [3, 4, 5]
    source_path: skills/setup/
```

- [ ] **Step 4: Verify YAML still parses**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
yq eval '.components."viv-typed-agents-setup".tiers' MANIFEST.yaml
```
Expected: `[3, 4, 5]`

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/ MANIFEST.yaml
git commit -m "feat(setup): scaffold /typedAgentSetup skill directory

Empty SKILL.md frontmatter, lib/, tests/ subdirs. Registered in
MANIFEST.yaml for tier 3+ installation."
```

---

### Task 4: Set up test infrastructure (smoke.test.sh + fixtures)

**Repo:** `/Users/viv/AI/vault/viv-typed-agents`

**Files:**
- Create: `skills/setup/tests/smoke.test.sh`
- Create: `skills/setup/tests/fixtures/greenfield/.gitkeep`
- Create: `skills/setup/tests/fixtures/brownfield-crypto/services/core/main.ts`
- Create: `skills/setup/tests/fixtures/brownfield-crypto/services/core/nest-cli.json`
- Create: `skills/setup/tests/fixtures/brownfield-crypto/services/ui/src/App.tsx`
- Create: `skills/setup/tests/fixtures/brownfield-crypto/services/ui/vite.config.ts`
- Create: `skills/setup/tests/fixtures/brownfield-crypto/package.json`

- [ ] **Step 1: Create greenfield fixture (empty marker)**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
mkdir -p skills/setup/tests/fixtures/greenfield
touch skills/setup/tests/fixtures/greenfield/.gitkeep
```

- [ ] **Step 2: Create brownfield-crypto fixture**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup/tests/fixtures
mkdir -p brownfield-crypto/services/core brownfield-crypto/services/ui/src
echo '{"name":"my-project","private":true}' > brownfield-crypto/package.json
echo "// nest entry" > brownfield-crypto/services/core/main.ts
echo '{"$schema":"https://json.schemastore.org/nest-cli"}' > brownfield-crypto/services/core/nest-cli.json
echo "export default function App(){return null;}" > brownfield-crypto/services/ui/src/App.tsx
echo "export default {};" > brownfield-crypto/services/ui/vite.config.ts
```

- [ ] **Step 3: Write smoke.test.sh skeleton**

Create `skills/setup/tests/smoke.test.sh`:

```bash
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
echo "Result: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 4: Make it executable and run**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x tests/smoke.test.sh
bash tests/smoke.test.sh
```
Expected: prints "Result: 0 pass, 0 fail" (no lib scripts yet) and exits 0.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/tests/
git commit -m "test(setup): scaffold smoke tests and fixture projects

Fixtures: greenfield (empty), brownfield-crypto (NestJS + React Vite).
Smoke test runs bash -n on every lib/*.sh. More tests added per
deterministic-script task."
```

---

## Phase 3 — Deterministic lib scripts (TDD per script)

### Task 5: `detect-state.sh` — greenfield vs brownfield

**Repo:** `/Users/viv/AI/vault/viv-typed-agents`

**Files:**
- Create: `skills/setup/lib/detect-state.sh`
- Modify: `skills/setup/tests/smoke.test.sh` (add `detect-state` tests)

**Contract:** `detect-state.sh <project-path>` prints `greenfield` or `brownfield` to stdout, exits 0.

- [ ] **Step 1: Write the failing test**

Append to `skills/setup/tests/smoke.test.sh`, before the final summary `echo`:

```bash
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
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
bash tests/smoke.test.sh
```
Expected: `FAIL: lib/detect-state.sh not found`, exit 1.

- [ ] **Step 3: Implement detect-state.sh**

Create `skills/setup/lib/detect-state.sh`:

```bash
#!/usr/bin/env bash
# detect-state.sh <project-path>
# Prints "greenfield" or "brownfield".
# Brownfield: contains source code outside .claude/.
# Greenfield: empty or only .claude/, .git/, README, LICENSE.

set -euo pipefail

target="${1:-}"
[ -n "$target" ] || { echo "usage: detect-state.sh <path>" >&2; exit 2; }
[ -d "$target" ] || { echo "not a directory: $target" >&2; exit 2; }

# Look for source files outside .claude/ and .git/.
found=$(find "$target" \
  -path "$target/.claude" -prune -o \
  -path "$target/.git" -prune -o \
  -type f \( \
    -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o \
    -name "*.vue" -o -name "*.svelte" -o \
    -name "*.go" -o -name "*.py" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" -o \
    -name "Dockerfile" -o -name "Dockerfile.*" -o -name "package.json" \
  \) -print -quit 2>/dev/null)

if [ -n "$found" ]; then
  echo "brownfield"
else
  echo "greenfield"
fi
```

- [ ] **Step 4: Make executable and run test**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x lib/detect-state.sh
bash tests/smoke.test.sh
```
Expected: `PASS: greenfield detected`, `PASS: brownfield detected`, exit 0.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/detect-state.sh skills/setup/tests/smoke.test.sh
git commit -m "feat(setup): detect-state.sh classifies project as greenfield/brownfield"
```

---

### Task 6: `discover-services.sh` — find candidate service folders

**Contract:** `discover-services.sh <project-path>` prints one folder path per line (relative to project-path), one per candidate service. Empty output if greenfield.

**Files:**
- Create: `skills/setup/lib/discover-services.sh`
- Modify: `skills/setup/tests/smoke.test.sh`

- [ ] **Step 1: Write failing test**

Append to `skills/setup/tests/smoke.test.sh`, before final summary:

```bash
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
```

- [ ] **Step 2: Run test, verify it fails**

```bash
bash tests/smoke.test.sh
```
Expected: `FAIL: lib/discover-services.sh not found`.

- [ ] **Step 3: Implement discover-services.sh**

Create `skills/setup/lib/discover-services.sh`:

```bash
#!/usr/bin/env bash
# discover-services.sh <project-path>
# Prints candidate service folders (one per line, relative to project-path).
# Looks under services/, apps/, packages/. Falls back to top-level folders
# with source code if no monorepo root exists.

set -euo pipefail

target="${1:-}"
[ -d "$target" ] || { echo "not a directory: $target" >&2; exit 2; }

SOURCE_GLOB='-name *.ts -o -name *.tsx -o -name *.js -o -name *.jsx -o -name *.vue -o -name *.svelte -o -name *.go -o -name *.py -o -name *.rs -o -name *.java -o -name *.rb'

has_source() {
  # $1: folder path. Returns 0 if folder contains any source file.
  find "$1" -type f \( $SOURCE_GLOB \) -print -quit 2>/dev/null | grep -q .
}

found_root=0
for root in services apps packages; do
  if [ -d "$target/$root" ]; then
    found_root=1
    for sub in "$target/$root"/*/; do
      [ -d "$sub" ] || continue
      if has_source "$sub"; then
        # Strip trailing slash and project-path prefix.
        rel="${sub%/}"
        rel="${rel#"$target/"}"
        echo "$rel"
      fi
    done
  fi
done

if [ "$found_root" = "0" ]; then
  # No monorepo root: scan top-level folders.
  for sub in "$target"/*/; do
    [ -d "$sub" ] || continue
    name=$(basename "$sub")
    case "$name" in .claude|.git|node_modules) continue;; esac
    if has_source "$sub"; then
      echo "$name"
    fi
  done
fi
```

- [ ] **Step 4: Run test**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x lib/discover-services.sh
bash tests/smoke.test.sh
```
Expected: `PASS: brownfield-crypto services discovered`, `PASS: greenfield: no services`.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/discover-services.sh skills/setup/tests/smoke.test.sh
git commit -m "feat(setup): discover-services.sh finds candidate service folders"
```

---

### Task 7: `classify-layer.sh` — apply skill detection signatures

**Contract:** `classify-layer.sh <project-path> <service-folder-rel> <skills-dir>` prints `backend`, `frontend`, or `ambiguous`. `skills-dir` defaults to `.claude/skills/`.

**Files:**
- Create: `skills/setup/lib/classify-layer.sh`
- Modify: `skills/setup/tests/smoke.test.sh`
- Create test asset: `skills/setup/tests/fixtures/_skills/backend/nestjs-backend/SKILL.md`
- Create test asset: `skills/setup/tests/fixtures/_skills/frontend/react-frontend/SKILL.md`

- [ ] **Step 1: Create skill fixtures for testing**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup/tests/fixtures
mkdir -p _skills/backend/nestjs-backend _skills/frontend/react-frontend

cat > _skills/backend/nestjs-backend/SKILL.md <<'EOF'
---
name: nestjs-backend
detection:
  layer: backend
  entry_files: [main.ts, nest-cli.json]
  file_globs: ["src/**/*.module.ts"]
---
EOF

cat > _skills/frontend/react-frontend/SKILL.md <<'EOF'
---
name: react-frontend
detection:
  layer: frontend
  config_files: [vite.config.ts, vite.config.js]
  file_globs: ["**/*.tsx", "**/*.jsx"]
---
EOF
```

- [ ] **Step 2: Write failing tests**

Append to `tests/smoke.test.sh`:

```bash
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
```

- [ ] **Step 3: Run, verify fails**

```bash
bash tests/smoke.test.sh
```
Expected: `FAIL: lib/classify-layer.sh not found`.

- [ ] **Step 4: Implement classify-layer.sh**

Create `skills/setup/lib/classify-layer.sh`:

```bash
#!/usr/bin/env bash
# classify-layer.sh <project-path> <service-folder-rel> <skills-dir>
# Reads detection signatures from skills-dir/**/SKILL.md frontmatter,
# applies them to the service folder, prints: backend | frontend | ambiguous.

set -euo pipefail

project="${1:-}"
service="${2:-}"
skills_dir="${3:-.claude/skills}"

[ -d "$project/$service" ] || { echo "ambiguous"; exit 0; }
[ -d "$skills_dir" ] || { echo "ambiguous"; exit 0; }

folder="$project/$service"
matched_backend=0
matched_frontend=0

# Iterate all SKILL.md files with a `detection:` block.
while IFS= read -r skill_file; do
  # Extract frontmatter (between first two --- markers).
  fm=$(awk '/^---$/{c++;next} c==1{print} c>=2{exit}' "$skill_file")
  # Skip if no detection block.
  echo "$fm" | grep -q "^detection:" || continue

  # Parse layer.
  layer=$(echo "$fm" | yq eval '.detection.layer' -)
  [ "$layer" = "null" ] && continue

  # Check entry_files: presence of any file at folder root.
  hit=0
  for key in entry_files config_files; do
    count=$(echo "$fm" | yq eval ".detection.$key | length" - 2>/dev/null || echo 0)
    [ "$count" = "null" ] && count=0
    for i in $(seq 0 $((count-1))); do
      fname=$(echo "$fm" | yq eval ".detection.$key[$i]" -)
      if [ -f "$folder/$fname" ]; then hit=1; break; fi
    done
    [ "$hit" = "1" ] && break
  done

  # Check file_globs: any file matching any glob.
  if [ "$hit" = "0" ]; then
    count=$(echo "$fm" | yq eval ".detection.file_globs | length" - 2>/dev/null || echo 0)
    [ "$count" = "null" ] && count=0
    for i in $(seq 0 $((count-1))); do
      glob=$(echo "$fm" | yq eval ".detection.file_globs[$i]" -)
      # Use find with -name on the last path segment for simple globs;
      # for "**/*.ext" patterns we just match the extension.
      ext="${glob##*.}"
      if [ -n "$ext" ] && find "$folder" -type f -name "*.$ext" -print -quit 2>/dev/null | grep -q .; then
        hit=1; break
      fi
    done
  fi

  if [ "$hit" = "1" ]; then
    case "$layer" in
      backend)  matched_backend=1 ;;
      frontend) matched_frontend=1 ;;
    esac
  fi
done < <(find "$skills_dir" -name SKILL.md)

if [ "$matched_backend" = "1" ] && [ "$matched_frontend" = "1" ]; then
  echo "ambiguous"
elif [ "$matched_backend" = "1" ]; then
  echo "backend"
elif [ "$matched_frontend" = "1" ]; then
  echo "frontend"
else
  echo "ambiguous"
fi
```

- [ ] **Step 5: Make executable, run test**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x lib/classify-layer.sh
bash tests/smoke.test.sh
```
Expected: `PASS: services/core -> backend`, `PASS: services/ui -> frontend`.

- [ ] **Step 6: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/classify-layer.sh skills/setup/tests/
git commit -m "feat(setup): classify-layer.sh applies skill detection signatures"
```

---

### Task 8: `lookup-agent.sh` — resolve (layer, business_domain, type) → agent name

**Contract:** `lookup-agent.sh <agents-dir> <layer> <business_domain> <type>` prints the agent name (frontmatter `name`) or exits 1 with no output if no match.

**Files:**
- Create: `skills/setup/lib/lookup-agent.sh`
- Modify: `skills/setup/tests/smoke.test.sh`
- Test assets: `skills/setup/tests/fixtures/_agents/backend/backend-crypto-implementer.md`, `_agents/frontend/frontend-crypto-implementer.md`

- [ ] **Step 1: Create agent fixtures**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup/tests/fixtures
mkdir -p _agents/backend _agents/frontend

cat > _agents/backend/backend-crypto-implementer.md <<'EOF'
---
name: backend-crypto-implementer
type: implementer
domain: backend
business_domain: crypto
description: stub
---
EOF

cat > _agents/frontend/frontend-crypto-implementer.md <<'EOF'
---
name: frontend-crypto-implementer
type: implementer
domain: frontend
business_domain: crypto
description: stub
---
EOF
```

- [ ] **Step 2: Write failing test**

Append to `tests/smoke.test.sh`:

```bash
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
```

- [ ] **Step 3: Run, verify fails**

```bash
bash tests/smoke.test.sh
```

- [ ] **Step 4: Implement lookup-agent.sh**

Create `skills/setup/lib/lookup-agent.sh`:

```bash
#!/usr/bin/env bash
# lookup-agent.sh <agents-dir> <domain> <business_domain> <type>
# Prints the matching agent's `name` from frontmatter. Exits 1 if no match.

set -euo pipefail

agents_dir="${1:?agents-dir required}"
want_domain="${2:?domain required}"
want_bd="${3:?business_domain required}"
want_type="${4:?type required}"

[ -d "$agents_dir" ] || { exit 1; }

match=""
while IFS= read -r f; do
  fm=$(awk '/^---$/{c++;next} c==1{print} c>=2{exit}' "$f")
  d=$(echo "$fm" | yq eval '.domain // ""' -)
  bd=$(echo "$fm" | yq eval '.business_domain // ""' -)
  t=$(echo "$fm" | yq eval '.type // ""' -)
  if [ "$d" = "$want_domain" ] && [ "$bd" = "$want_bd" ] && [ "$t" = "$want_type" ]; then
    name=$(echo "$fm" | yq eval '.name' -)
    if [ -n "$match" ]; then
      echo "multiple matches for $want_domain/$want_bd/$want_type" >&2
      exit 1
    fi
    match="$name"
  fi
done < <(find "$agents_dir" -name "*.md")

[ -n "$match" ] || exit 1
echo "$match"
```

- [ ] **Step 5: Run test**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x lib/lookup-agent.sh
bash tests/smoke.test.sh
```
Expected: 3 PASS lines for lookup-agent.

- [ ] **Step 6: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/lookup-agent.sh skills/setup/tests/
git commit -m "feat(setup): lookup-agent.sh resolves (domain,business_domain,type) -> agent"
```

---

### Task 9: `write-routing.sh` — generate / merge routing-table.json

**Contract:** `write-routing.sh <output-path> <plan-json>` writes routing-table.json. `plan-json` is a JSON document describing the routes. If output-path exists, merges by `domain` key (preserves entries the user has hand-edited).

`plan-json` shape:
```json
[
  {"domain":"backend","paths":["services/core/**"],"implementer":"backend-crypto-implementer","reviewer":"backend-crypto-reviewer","enforced":true},
  ...
]
```

**Files:**
- Create: `skills/setup/lib/write-routing.sh`
- Modify: `skills/setup/tests/smoke.test.sh`

- [ ] **Step 1: Write failing test**

Append to `tests/smoke.test.sh`:

```bash
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
```

- [ ] **Step 2: Run, verify fails**

```bash
bash tests/smoke.test.sh
```

- [ ] **Step 3: Implement write-routing.sh**

Create `skills/setup/lib/write-routing.sh`:

```bash
#!/usr/bin/env bash
# write-routing.sh <output-path> <plan-json-file>
# Writes or merges routing-table.json. Plan is a JSON array of route objects.
# Merge rule: by `domain` key. Existing entries keep paths/implementer/reviewer
# if they differ from plan (user may have hand-edited); new entries are added.

set -euo pipefail

out="${1:?output-path required}"
plan="${2:?plan-json-file required}"

[ -f "$plan" ] || { echo "plan not found: $plan" >&2; exit 2; }

mkdir -p "$(dirname "$out")"

if [ ! -f "$out" ]; then
  # Fresh write.
  jq --slurpfile p "$plan" '{
    "$schema": "./schema/routing-table.schema.json",
    "version": "1.0",
    "routes": $p[0]
  }' <<<'{}' > "$out"
  exit 0
fi

# Merge: keep existing entries unchanged; append new ones whose domain is absent.
tmp=$(mktemp)
jq --slurpfile p "$plan" '
  .routes as $existing
  | ($p[0] | map(select(.domain as $d | ($existing | map(.domain) | index($d)) == null))) as $new
  | .routes = $existing + $new
' "$out" > "$tmp" && mv "$tmp" "$out"
```

- [ ] **Step 4: Run test**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x lib/write-routing.sh
bash tests/smoke.test.sh
```
Expected: `PASS: write fresh routing-table`, `PASS: idempotent re-run`.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/write-routing.sh skills/setup/tests/
git commit -m "feat(setup): write-routing.sh emits routing-table.json with idempotent merge"
```

---

### Task 10: `merge-settings.sh` — merge hook settings.json fragment

**Contract:** `merge-settings.sh <consumer-settings> <fragment-path>` deep-merges the fragment JSON into the consumer's settings.json (creating it if absent). Existing user keys are preserved.

**Files:**
- Create: `skills/setup/lib/merge-settings.sh`
- Modify: `skills/setup/tests/smoke.test.sh`

- [ ] **Step 1: Write failing test**

Append to `tests/smoke.test.sh`:

```bash
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
```

- [ ] **Step 2: Run, verify fails**

- [ ] **Step 3: Implement merge-settings.sh**

Create `skills/setup/lib/merge-settings.sh`:

```bash
#!/usr/bin/env bash
# merge-settings.sh <consumer-settings.json> <fragment.json>
# Deep-merges fragment into consumer settings. Creates consumer file if missing.

set -euo pipefail

target="${1:?settings.json path required}"
fragment="${2:?fragment.json path required}"

[ -f "$fragment" ] || { echo "fragment not found: $fragment" >&2; exit 2; }

if [ ! -f "$target" ]; then
  cp "$fragment" "$target"
  exit 0
fi

tmp=$(mktemp)
# jq's * operator does recursive merge with right side winning at scalar leaves.
# For arrays (like hooks.PreToolUse), concatenate.
jq -s '
  def merge_array_aware(a; b):
    reduce (b | keys[]) as $k (a;
      if (.[$k] | type) == "array" and (b[$k] | type) == "array"
      then .[$k] = (.[$k] + b[$k] | unique_by(. | tostring))
      elif (.[$k] | type) == "object" and (b[$k] | type) == "object"
      then .[$k] = merge_array_aware(.[$k]; b[$k])
      else .[$k] = b[$k]
      end);
  merge_array_aware(.[0]; .[1])
' "$target" "$fragment" > "$tmp" && mv "$tmp" "$target"
```

- [ ] **Step 4: Run test**

```bash
chmod +x lib/merge-settings.sh
bash tests/smoke.test.sh
```
Expected: `PASS: merge preserves user keys and adds hook`.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/merge-settings.sh skills/setup/tests/
git commit -m "feat(setup): merge-settings.sh deep-merges hook fragment"
```

---

### Task 11: `adapt-claude-md.sh` — copy and adapt CLAUDE.md template

**Contract:** `adapt-claude-md.sh <template-path> <output-path> <project-name>` copies the template to output-path, replacing `<PROJECT_NAME>` placeholders. If output exists, prints a warning and exits 0 without writing.

**Files:**
- Create: `skills/setup/lib/adapt-claude-md.sh`
- Modify: `skills/setup/tests/smoke.test.sh`

- [ ] **Step 1: Write failing test**

Append to `tests/smoke.test.sh`:

```bash
echo
echo "--- adapt-claude-md.sh ---"
if [ -x lib/adapt-claude-md.sh ]; then
  TMP=$(mktemp -d)
  echo "# <PROJECT_NAME>" > "$TMP/template.md"
  bash lib/adapt-claude-md.sh "$TMP/template.md" "$TMP/CLAUDE.md" "viv-app"
  out=$(cat "$TMP/CLAUDE.md")
  [ "$out" = "# viv-app" ] && ok "template adapted" || ko "got: $out"

  # Existing CLAUDE.md should be skipped.
  echo "# existing" > "$TMP/CLAUDE.md"
  bash lib/adapt-claude-md.sh "$TMP/template.md" "$TMP/CLAUDE.md" "viv-app"
  out=$(cat "$TMP/CLAUDE.md")
  [ "$out" = "# existing" ] && ok "existing CLAUDE.md preserved" || ko "got: $out"
  rm -rf "$TMP"
else
  ko "lib/adapt-claude-md.sh not found"
fi
```

- [ ] **Step 2: Run, verify fails**

- [ ] **Step 3: Implement adapt-claude-md.sh**

Create `skills/setup/lib/adapt-claude-md.sh`:

```bash
#!/usr/bin/env bash
# adapt-claude-md.sh <template-path> <output-path> <project-name>
# Copies template to output, substituting <PROJECT_NAME>. Skips if output exists.

set -euo pipefail

template="${1:?template required}"
out="${2:?output required}"
name="${3:?project-name required}"

[ -f "$template" ] || { echo "template not found: $template" >&2; exit 2; }

if [ -f "$out" ]; then
  echo "WARN: $out exists; not overwriting" >&2
  exit 0
fi

# Use awk for substitution (safer than sed with arbitrary names).
awk -v name="$name" '{ gsub("<PROJECT_NAME>", name); print }' "$template" > "$out"
```

- [ ] **Step 4: Run test**

```bash
chmod +x lib/adapt-claude-md.sh
bash tests/smoke.test.sh
```
Expected: 2 new PASS lines.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/lib/adapt-claude-md.sh skills/setup/tests/
git commit -m "feat(setup): adapt-claude-md.sh applies template with project-name substitution"
```

---

## Phase 4 — SKILL.md conversation layer

### Task 12: Write the full SKILL.md prompt

**Files:**
- Modify: `skills/setup/SKILL.md` (replace body)

The SKILL.md instructs the LLM how to orchestrate the wizard. It calls the lib scripts for deterministic work and uses `AskUserQuestion` for interactive choices.

- [ ] **Step 1: Replace SKILL.md body**

Replace `skills/setup/SKILL.md` content with:

````markdown
---
name: typedAgentSetup
description: >
  Use after running viv-typed-agents/scripts/install.sh on a consumer project.
  Configures the routing-table, merges hook settings, and adapts the CLAUDE.md
  template based on the project's structure and selected business domain.
  Activated via /typedAgentSetup.
tier_required: 3
---

# /typedAgentSetup — Wizard for completing typed-agents post-install configuration

You are running the typed-agents post-install wizard inside a consumer project. Your job is to produce a working `.claude/routing/routing-table.json` (and optionally merge `settings.json` and adapt `CLAUDE.md`) based on the project's structure and a business-domain selection.

## Preconditions you MUST verify before starting

Run these checks in order. If any fails, abort with the listed message and do not proceed.

1. `.claude/agents/` must exist.
   If missing: `"This skill requires tier 3+ install. Re-run scripts/install.sh with --tier 3 or higher."`
2. `.claude/routing/` must exist.
   Same message.
3. At least one agent file under `.claude/agents/` must have a `business_domain` frontmatter field. Check with:
   ```bash
   grep -l "^business_domain:" .claude/agents/**/*.md | head -1
   ```
   If empty: `"viv-agents needs to be upgraded to expose business_domain. Run: ./scripts/upgrade.sh viv-agents, then re-run /typedAgentSetup."`

## The 5 phases

### Phase 0 — Detect project state

Run:
```bash
bash .claude/skills/setup/lib/detect-state.sh .
```
Output is `greenfield` or `brownfield`. Remember this.

### Phase 1 — Discover service folders (brownfield only)

If brownfield, run:
```bash
bash .claude/skills/setup/lib/discover-services.sh .
```
Each output line is a candidate folder.

### Phase 2 — Classify each folder

For each candidate folder, run:
```bash
bash .claude/skills/setup/lib/classify-layer.sh . <folder> .claude/skills
```
Output: `backend`, `frontend`, or `ambiguous`.

Build a table in your head:
```
folder           layer
services/core    backend
services/ui      frontend
services/legacy  ambiguous
```

### Phase 3 — Ask the user to select a business domain

Discover available business domains:
```bash
grep -rh "^business_domain:" .claude/agents/ | awk '{print $2}' | sort -u
```
Filter out `cross-cutting` from the list shown to the user.

Use `AskUserQuestion` to present a single-select list, like:
```
"Which business domain does this project work in?"
Options: ["Crypto", "WaaS", "Generic"]
```

### Phase 4 — Build the routing plan and confirm

For the selected business domain `BD`, for each (layer, role) pair in `{(backend, implementer), (backend, reviewer), (frontend, implementer), (frontend, reviewer)}`:
```bash
bash .claude/skills/setup/lib/lookup-agent.sh .claude/agents/ <layer> <BD> <role>
```
If any lookup fails (exit non-zero), abort and tell the user:
```
"Missing agents for business domain '<BD>':
  - <layer>-<BD>-<role>  (no agent matches)

Options:
  1. Re-run install.sh with the missing agents
  2. Select a different business domain
  3. Manually edit .claude/routing/routing-table.json
"
```

For ambiguous folders from Phase 2, ask the user (one `AskUserQuestion` per folder) which layer it belongs to. Accept: `backend`, `frontend`, or `skip`.

For **greenfield**, skip the discovery. Ask the user with `AskUserQuestion`:
- "What is the path to your backend code?" (default: `services/core`)
- "What is the path to your frontend code?" (default: `services/ui`)

Build a JSON plan with the resolved routes:
```json
[
  {"domain":"backend","paths":["services/core/**"],"implementer":"backend-crypto-implementer","reviewer":"backend-crypto-reviewer","enforced":true},
  {"domain":"frontend","paths":["services/ui/**"],"implementer":"frontend-crypto-implementer","reviewer":"frontend-crypto-reviewer","enforced":true}
]
```

Then add the canonical cross-cutting entries by copying `infra-devops`, `testing`, and `docs` routes verbatim from `viv-routing`'s template (if available at `.claude/routing/routing-table.template.json`; otherwise use the hard-coded defaults shown in the spec).

Present the plan to the user in a readable table and ask:
> "Confirm this routing? [Y/n/edit]"

If `edit`, accept changes interactively (add/remove paths, reassign).

### Phase 5 — Write and merge

Write the plan to a temp file, then run:
```bash
bash .claude/skills/setup/lib/write-routing.sh .claude/routing/routing-table.json /tmp/plan.json
```

Conditionally merge hook settings:
```bash
if [ -f .claude/hooks/settings.json.fragment ]; then
  bash .claude/skills/setup/lib/merge-settings.sh .claude/settings.json .claude/hooks/settings.json.fragment
fi
```

Conditionally adapt CLAUDE.md:
```bash
if [ -f .claude/orchestration/CLAUDE.template.md ]; then
  project_name=$(basename "$(pwd)")
  bash .claude/skills/setup/lib/adapt-claude-md.sh \
    .claude/orchestration/CLAUDE.template.md CLAUDE.md "$project_name"
fi
```

## Final output to the user

Print a summary:
```
Setup complete:
  ✓ .claude/routing/routing-table.json   (N routes)
  ✓ .claude/settings.json                (merged or skipped — say which)
  ✓ CLAUDE.md                            (adapted or skipped — say which)

Next: dispatch a typed agent. Example: ask Claude Code to implement
something in services/core — it will route to the configured backend
implementer.
```

## Error handling rules

- Never write a partial routing-table. If any agent lookup fails after the user confirms the plan, abort before calling write-routing.sh.
- Never overwrite a hand-edited CLAUDE.md. Skip with warning.
- Never silently substitute generic agents for missing business-domain agents.
- If the user picks a business domain that lacks full coverage, list every missing agent and offer the three options from the spec.
````

- [ ] **Step 2: Verify SKILL.md frontmatter parses**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
python3 -c "
import yaml
with open('SKILL.md') as f: content = f.read()
fm = yaml.safe_load(content.split('---', 2)[1])
assert fm['name'] == 'typedAgentSetup'
assert fm['tier_required'] == 3
print('OK')
"
```
Expected: `OK`.

- [ ] **Step 3: Run smoke tests still pass**

```bash
bash tests/smoke.test.sh
```
Expected: all PASS, exit 0.

- [ ] **Step 4: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/SKILL.md
git commit -m "feat(setup): write SKILL.md procedural instructions for /typedAgentSetup

5-phase wizard: detect state -> discover services -> classify layer ->
select business domain -> confirm + write. Delegates deterministic work
to lib/*.sh."
```

---

## Phase 5 — Integration and docs

### Task 13: End-to-end fixture test (brownfield-crypto golden output)

**Files:**
- Create: `skills/setup/tests/fixtures/brownfield-crypto/expected-routing.json`
- Create: `skills/setup/tests/e2e.test.sh`

This test exercises the lib scripts end-to-end (skipping the LLM conversation) on the brownfield-crypto fixture.

- [ ] **Step 1: Define expected routing-table.json**

Create `skills/setup/tests/fixtures/brownfield-crypto/expected-routing.json`:

```json
{
  "$schema": "./schema/routing-table.schema.json",
  "version": "1.0",
  "routes": [
    {"domain":"backend","paths":["services/core/**"],"implementer":"backend-crypto-implementer","reviewer":"backend-crypto-reviewer","enforced":true},
    {"domain":"frontend","paths":["services/ui/**"],"implementer":"frontend-crypto-implementer","reviewer":"frontend-crypto-reviewer","enforced":true}
  ]
}
```

- [ ] **Step 2: Write e2e.test.sh**

Create `skills/setup/tests/e2e.test.sh`:

```bash
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
```

- [ ] **Step 3: Add the backend-crypto-reviewer and frontend-crypto-reviewer fixture agents**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup/tests/fixtures/_agents

cat > backend/backend-crypto-reviewer.md <<'EOF'
---
name: backend-crypto-reviewer
type: reviewer
domain: backend
business_domain: crypto
description: stub
---
EOF

cat > frontend/frontend-crypto-reviewer.md <<'EOF'
---
name: frontend-crypto-reviewer
type: reviewer
domain: frontend
business_domain: crypto
description: stub
---
EOF
```

- [ ] **Step 4: Run e2e test**

```bash
cd /Users/viv/AI/vault/viv-typed-agents/skills/setup
chmod +x tests/e2e.test.sh
bash tests/e2e.test.sh
```
Expected: `PASS: brownfield-crypto e2e matches golden output`.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add skills/setup/tests/
git commit -m "test(setup): e2e fixture test producing golden routing-table.json"
```

---

### Task 14: Teach `install.sh` to copy the setup skill

**Files:**
- Modify: `scripts/install.sh` (add handling for the `viv-typed-agents-setup` MANIFEST entry, since it lives in the same repo, not a remote one)

- [ ] **Step 1: Read install.sh component installation loop**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
grep -n "repo:" scripts/install.sh | head
grep -n "components:" scripts/install.sh | head
```
Locate the loop that iterates `MANIFEST.yaml`'s `components:` and clones each repo.

- [ ] **Step 2: Add a branch for `repo: <self>` entries**

In `scripts/install.sh`, find the block that clones each component. Before the `git clone` call, add:

```bash
if [ "$REPO" = "<self>" ]; then
  # Local component — copy directly from this repo, not a remote clone.
  SRC_PATH="$(dirname "$0")/../$(yq eval ".components.\"$COMP\".source_path" MANIFEST.yaml)"
  TARGET_REL="$(yq eval ".components.\"$COMP\".target_path" MANIFEST.yaml)"
  mkdir -p "$TARGET/$TARGET_REL"
  cp -R "$SRC_PATH/." "$TARGET/$TARGET_REL/"
  continue
fi
```

(Exact placement depends on the script's structure; the `continue` must skip the rest of the per-component clone loop body.)

- [ ] **Step 3: Verify by dry-running install.sh against a temp project**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
TMP=$(mktemp -d)
bash scripts/install.sh "$TMP" --tier 5 --dry-run
```
Expected output should include a line referencing `skills/setup` going to `.claude/skills/setup/`.

- [ ] **Step 4: Real install + verify**

```bash
bash scripts/install.sh "$TMP" --tier 5
test -f "$TMP/.claude/skills/setup/SKILL.md" && echo "OK skill copied" || echo "FAIL"
test -x "$TMP/.claude/skills/setup/lib/detect-state.sh" && echo "OK script executable" || echo "FAIL"
rm -rf "$TMP"
```
Expected: both `OK` lines.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/install.sh
git commit -m "feat(install): copy local setup skill component to consumer

When MANIFEST.yaml component has repo: <self>, copy from source_path
directly instead of cloning a remote repo."
```

---

### Task 15: Update README with `/typedAgentSetup` mention

**Files:**
- Modify: `README.md` (insert section after "Install")

- [ ] **Step 1: Read current README "What you get post-install" section**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
grep -n "Next steps after install" README.md
```

- [ ] **Step 2: Insert a new section between "Install" and "What you get post-install"**

Add this section to `README.md`:

```markdown
## After install — run the setup wizard

For tier 3+ installs, run inside the consumer project:

\`\`\`
claude
> /typedAgentSetup
\`\`\`

The wizard scans the project (or asks for paths if greenfield), asks
which business domain you work in (Crypto, WaaS, Generic), and writes
the routing-table, merges hook settings, and adapts CLAUDE.md.

See \`architecture/specs/2026-05-09-typed-agent-setup.md\` for the full
behavior.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add README.md
git commit -m "docs(readme): document /typedAgentSetup wizard"
```

---

## Self-review checklist (run after all tasks)

- [ ] All spec sections have at least one task: Phase 0 (Task 5), Phase 1 (Task 6), Phase 2 (Task 7), Phase 3 (Tasks 8 + 12), Phase 4 (Task 12), Phase 5 (Tasks 9, 10, 11), idempotency (Task 9 step 1 idempotency test), migrations (Tasks 1, 2), tier gating (Task 12 conditional blocks), upgrade path (Task 12 precondition check)
- [ ] No `TBD` / `TODO` / `placeholder` strings in this plan
- [ ] All lib scripts have a contract documented at top + a test before implementation
- [ ] All commits are small (one capability per commit)
- [ ] `business_domain` field name is consistent across migration, fixtures, lookup, and SKILL.md
- [ ] `detection` field name is consistent across viv-skills migration, fixtures, and `classify-layer.sh`
