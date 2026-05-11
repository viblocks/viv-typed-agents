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

For the selected business domain `BD`, determine which **layers are actually present** in this project:

- For **brownfield**: a layer is present if at least one service folder was classified as that layer in Phase 2 (after ambiguous-folder resolution).
- For **greenfield**: a layer is present if the user provided a path for it in the path-input step.

For each present layer `L` ∈ {backend, frontend} and role `R` ∈ {implementer, reviewer}, run:

```bash
bash .claude/skills/setup/lib/lookup-agent.sh .claude/agents/ <L> <BD> <R>
```

If `L` is not present, do NOT run the lookup — that layer's route will not appear in the routing-table.

If any required lookup (for a present layer) fails (exit non-zero), abort and tell the user:
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

Conditionally adapt CLAUDE.md. The script supports three modes:
1. **Fresh file** — output does not exist: render template and write,
   wrapped in `<!-- viv-typed-agents:BEGIN -->` / `<!-- viv-typed-agents:END -->`
   markers.
2. **Existing file, no markers** — append the rendered managed block at the
   end of the existing file; content above is preserved byte-for-byte.
3. **Existing file with markers** — replace the content between the markers
   with the freshly rendered template. Idempotent: re-running produces the
   same file, and content outside the markers is left untouched.
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
  ✓ CLAUDE.md                            (created, appended, or refreshed — say which)

Next: dispatch a typed agent. Example: ask Claude Code to implement
something in services/core — it will route to the configured backend
implementer.
```

## Error handling rules

- Never write a partial routing-table. If any agent lookup fails after the user confirms the plan, abort before calling write-routing.sh.
- Never touch content outside the `<!-- viv-typed-agents:BEGIN/END -->` markers in CLAUDE.md. The managed block is the only zone the wizard owns; everything else (existing project rules, graphify navigation, custom conventions) is preserved byte-for-byte across mode 2 (initial append) and mode 3 (idempotent refresh).
- Never silently substitute generic agents for missing business-domain agents.
- If the user picks a business domain that lacks full coverage, list every missing agent and offer the three options from the spec.
