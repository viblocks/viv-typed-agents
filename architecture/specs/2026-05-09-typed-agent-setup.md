# Design — `/typedAgentSetup` skill

**Date:** 2026-05-09
**Status:** Draft (pending implementation plan)
**Owner:** viv-typed-agents

## Problem

Post-installation of viv-typed-agents requires four manual configuration steps:

1. Configure `routing-table.json` paths
2. Review workflow rules (data, no adaptation needed)
3. Merge `settings.json` fragment for hooks
4. Adapt `CLAUDE.template.md` for orchestration

These steps are documented but error-prone, repetitive, and block adoption. The product promises a turnkey installer but currently leaves the consumer with a non-functional configuration until they manually edit JSON, YAML, and Markdown across multiple files.

## Goal

Provide an interactive skill that completes post-install configuration automatically, leaving the consumer's project ready to use typed agents after one command.

## Non-goals

- Replace `install.sh`. The skill runs **after** installation; it does not download or place components.
- Configure workflow rule data (it is declarative and project-agnostic).
- Support arbitrary custom routing topologies. The skill targets the common cases (one business domain per project, standard monorepo layouts).

## User experience

```
$ claude
> /typedAgentSetup

> Detecting project state…
> Detected: brownfield (found package.json, services/, .git/)

> Scanning for service folders…
>   ✓ services/core    → backend  (signatures: main.ts, nest-cli.json)
>   ✓ services/ui      → frontend (signatures: 47 .tsx files, vite.config.ts)
>   ? services/legacy  → ambiguous

> Confirm classification? [Y/n/edit]
> Y

> Which business domain does this project work in?
>   1. Crypto / Blockchain
>   2. WaaS (Wallet-as-a-Service)
>   3. Generic (no specialized domain)
> 1

> Configuring:
>   ✓ .claude/routing/routing-table.json   (5 routes written)
>   ✓ .claude/settings.json                (hook fragment merged)
>   ✓ CLAUDE.md                            (template adapted, project name = "my-project")

> Setup complete. Typed agents are ready to dispatch.
```

## Design

### Architecture

```
viv-typed-agents/
└── skills/
    └── setup/
        └── SKILL.md                ← this skill
```

Installed by `install.sh` to:

```
<consumer>/
└── .claude/
    └── skills/setup/SKILL.md
```

Activated via the slash command `/typedAgentSetup` (registered automatically from the skill's frontmatter `name`).

### Tier gating

The skill is gated to **tier 3+** in `MANIFEST.yaml` because it depends on the routing component. Tier 1 and 2 consumers do not receive it.

Within tier 3+, the skill's output operations are **conditional on what is installed**:

| Tier | Hooks installed? | Orchestration-rules installed? | Phase 5 operations |
|------|------------------|-------------------------------|--------------------|
| 3 | No | No | Write `routing-table.json` only |
| 4 | Yes | No | Write `routing-table.json` + merge `settings.json` |
| 5 | Yes | Yes | Write `routing-table.json` + merge `settings.json` + adapt `CLAUDE.md` |

The skill detects what is installed at runtime by checking for the presence of `.claude/hooks/settings.json.fragment` (gates settings merge) and `.claude/orchestration/CLAUDE.template.md` (gates CLAUDE.md adaptation). It never asks the user for the tier — it reads the filesystem.

### Phases

#### Phase 0 — Project state detection

The skill classifies the consumer project as **brownfield** or **greenfield**:

- **Brownfield signals:** presence of `package.json`, `Dockerfile`, `*.go`, `*.py`, `*.rs`, or any source folder with code outside `.claude/`
- **Greenfield:** none of the above (empty or near-empty repository)

#### Phase 1 — Service folder discovery (stack-agnostic)

The skill identifies candidate service folders by scanning common monorepo roots:

1. If `services/`, `apps/`, or `packages/` exists, each subfolder with source code is a candidate.
2. Otherwise, top-level folders containing source code are candidates.
3. Source code = any of `.ts .js .tsx .jsx .vue .svelte .go .py .rs .java .rb`. The list lives in the skill's body as a documented constant; adding an extension is a single-line edit. Externalizing this list to data is deferred until a second consumer needs it.

For greenfield projects, this phase yields no candidates and the skill falls through to user input.

#### Phase 2 — Layer classification via skill-declared signatures

Each skill in `viv-skills` that introduces a stack declares detection signatures in its frontmatter:

```yaml
# viv-skills/backend/nestjs-backend/SKILL.md
---
name: nestjs-backend
detection:
  layer: backend
  entry_files: [main.ts, nest-cli.json]
  file_globs: ["src/**/*.module.ts"]
---
```

The setup skill scans installed skills, gathers signatures, applies them to each candidate folder. Each folder is tagged `backend`, `frontend`, or `ambiguous`.

**Conflict policy:** if a folder matches signatures from multiple layers, it is marked `ambiguous`. No priority rules. The user resolves conflicts in Phase 4.

#### Phase 3 — Business domain selection

The skill discovers available business domains by scanning `.claude/agents/`. Each agent declares:

```yaml
# .claude/agents/backend/backend-crypto-implementer.md
---
name: backend-crypto-implementer
type: implementer
domain: backend
business_domain: crypto         # ← new field
---
```

The skill groups agents by `business_domain`, presents a numbered list to the user, and accepts a single selection.

**Mapping:** the user picks **one** business domain. The skill maps that selection to backend + frontend agents using this lookup rule:

> For each layer `L` ∈ {backend, frontend} and role `R` ∈ {implementer, reviewer}, find the agent file in `.claude/agents/` where frontmatter satisfies `domain == L AND business_domain == <selected> AND type == R`. There must be exactly one match.

```
selected: crypto
  → backend paths get the agent where domain=backend, business_domain=crypto, type=implementer
                    (= backend-crypto-implementer) + the corresponding reviewer
  → frontend paths get the agent where domain=frontend, business_domain=crypto, type=implementer
                    (= frontend-crypto-implementer) + the corresponding reviewer
```

**Incomplete combo policy:** if any of the four (layer × role) lookups returns zero matches for the selected business domain, the skill **aborts** with an explicit error listing the missing agents:

```
Selected business domain 'waas' but missing required agents:
  - frontend-waas-implementer (no agent with domain=frontend, business_domain=waas, type=implementer)
  - frontend-waas-reviewer    (no agent with domain=frontend, business_domain=waas, type=reviewer)

Options:
  1. Re-run install.sh with the missing agents (--agents frontend-waas-implementer,...)
  2. Select a different business domain (one that has full backend+frontend coverage)
  3. Manually edit .claude/routing/routing-table.json to use 'generic' agents for frontend
```

No silent fallback to `generic`. The skill never substitutes agents the user did not select.

Cross-cutting agents (`infra-devops-*`, `dev-testing-strategy-reviewer`, `security-reviewer`) are always assigned to their canonical paths regardless of business domain. Canonical paths come from `viv-routing/routing-table.template.json` (the existing template provides the `infra-devops`, `testing`, and `docs` route entries verbatim).

#### Phase 4 — Confirmation and correction

The skill presents the proposed routing in a single screen:

```
Proposed routing:
  backend  services/core/**, packages/shared/**  → backend-crypto-implementer
  frontend services/ui/**                        → frontend-crypto-implementer
  infra    Dockerfile, .github/workflows/**      → infra-devops-implementer
  testing  **/*.spec.ts, **/*.test.ts            → dev-testing-strategy-reviewer

Confirm? [Y/n/edit]
```

`edit` opens an interactive correction loop where the user can reassign folders to layers, add/remove paths, or change the business domain.

For **greenfield** projects, Phase 4 begins immediately after Phase 0 — the skill asks the user for backend, frontend, and any additional paths in plain text, then applies the same business domain mapping.

#### Phase 5 — Write and merge

Three output operations, all idempotent:

1. **`routing-table.json`** — generate from the confirmed plan. If the file already exists, merge route entries:
   - For each new route: if the `domain` already has an entry, replace its `paths`/`implementer`/`reviewer` only if they differ; otherwise leave intact
   - Never delete existing routes the user has hand-edited

2. **`settings.json`** — merge the hook fragment from the installed `.claude/hooks/settings.json.fragment` (if hooks are installed). Use a non-destructive deep merge: existing user keys are preserved; only typed-agents hook entries are added or updated.

3. **`CLAUDE.md`** — if a `CLAUDE.template.md` is present in `.claude/orchestration/`, copy it to the project root as `CLAUDE.md`, replacing placeholders (`<PROJECT_NAME>`, etc.). If `CLAUDE.md` already exists, print a warning and skip — the user owns it.

### Idempotency

Re-running the skill is safe:

- Existing `routing-table.json` → merged, not overwritten
- Existing `settings.json` → merged, not overwritten
- Existing `CLAUDE.md` → skipped with warning

A user who started with backend-only and later adds frontend can re-run the skill, select the same business domain, and get the new frontend route appended without losing prior configuration.

## Migrations required

This design has **two prerequisite migrations** outside the skill itself:

### Migration 1 — `viv-agents` adds `business_domain` field

Every agent file in `viv-agents/` (12+ files) gets a `business_domain` field in its frontmatter:

| Agent | `business_domain` |
|-------|------------------|
| `backend-implementer`, `backend-reviewer` | `generic` |
| `frontend-implementer`, `frontend-reviewer` | `generic` |
| `backend-crypto-*`, `frontend-crypto-*` | `crypto` |
| `backend-waas-*`, `frontend-waas-*` | `waas` |
| `infra-devops-*`, `security-reviewer`, `dev-testing-strategy-reviewer` | `cross-cutting` |

This is a localized one-line change per file.

### Migration 2 — `viv-skills` adds `detection` field where applicable

Skills that introduce a stack get a `detection` frontmatter block. Domain skills (e.g., `crypto-backend` knowledge) don't need it. Examples to migrate first:

- `nestjs-backend` → `layer: backend`, entries for `main.ts`, `nest-cli.json`
- `react-crypto-frontend` → `layer: frontend`, globs for `*.tsx`, config for `vite.config.*`

Skills that don't introduce a stack (pure domain knowledge) are not touched.

### Upgrade path for existing installs

Consumers who installed viv-typed-agents before this change need to refresh their `.claude/agents/` to pick up the new `business_domain` field. The path:

1. In the consumer project, run the installer's upgrade flow against the bumped MANIFEST:
   ```
   curl -sL .../scripts/upgrade.sh | bash -s -- viv-agents
   ```
   This re-clones viv-agents at the new SHA and copies agent files over the consumer's `.claude/agents/`.

2. Then run `/typedAgentSetup` to (re)configure routing using the new field.

**Trade-off:** `upgrade.sh` overwrites `.claude/agents/*` non-destructively at the file level — if the consumer hand-edited an agent file, those edits are lost. Agent files are intended to be product-provided, not hand-edited. The README will state this contract explicitly. Hand-edits belong in a separate file (e.g., `.claude/agents/local/`) which the installer does not touch.

A migration script that adds the `business_domain` field in-place (preserving hand-edits) is out of scope for v1. The product contract is: agent files are managed by the installer.

## Error handling

| Scenario | Behavior |
|----------|----------|
| `.claude/agents/` missing (tier 1 or 2 by mistake) | Skill aborts with a clear message: "This skill requires tier 3+. Re-run install.sh with --tier 3 or higher." |
| `.claude/routing/` missing | Same as above |
| `business_domain` field missing on agents (pre-migration) | Skill aborts: "viv-agents requires migration to add `business_domain` frontmatter field. See architecture/specs/2026-05-09-typed-agent-setup.md → Migration 1." |
| User rejects all confirmation prompts | Skill exits without writing |
| Path provided by user does not exist (greenfield) | Skill warns and asks again |
| Conflict between detected and existing routing-table | User decides per-route in the merge step |

## Testing

- **Unit-equivalent tests via fixture projects:** create three `tests/fixtures/` directories (greenfield, brownfield-crypto, brownfield-waas) and verify the generated `routing-table.json` matches the expected output.
- **Idempotency test:** run the skill twice on the same fixture; assert outputs are identical.
- **Conflict test:** start with a hand-edited `routing-table.json`, run the skill, verify hand-edits are preserved.
- **Negative tests:** missing tiers, missing fields — assert the skill aborts cleanly.

The skill itself runs in Claude Code and is hard to unit-test in isolation. Integration tests exercise the deterministic pieces (signature matching, JSON merge, template substitution) via the underlying bash/utility code that the skill calls.

## Open questions

- Should the skill emit a `setup-complete.lock` file or similar marker to detect "first run vs re-run" without inspecting all output files? **Tentative:** no — output files are the source of truth.
- Where do the layer signatures aggregate at runtime? Each skill declares its own; the setup skill scans all installed skills. No central registry. **Confirmed.**
- How does the user add a path that wasn't auto-detected (e.g., a fourth service)? **Confirmed:** Phase 4's `edit` mode supports adding arbitrary paths.

## Out of scope (deferred)

- Multi-business-domain projects (e.g., backend in Crypto, frontend in WaaS): the user edits `routing-table.json` manually. The skill assumes one business domain per project.
- Programmatic invocation (CI use case): the skill is interactive; if needed later, a `--non-interactive` mode with config file input can be added.
- Migration of an already-typed-agents-configured project from one business domain to another (e.g., crypto → waas). Out of scope for v1.
