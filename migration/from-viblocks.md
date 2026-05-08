# Migration from viblocks-ai

This document describes the migration plan from viblocks-ai's monolithic `.claude/` setup to the six-component redesigned strategy.

## Current state (2026-05-08)

| Component | Status | Notes |
|---|---|---|
| viv-skills | ✓ Extracted and live | https://github.com/viblocks/viv-skills |
| viv-agents | ✓ Extracted and live | https://github.com/viblocks/viv-agents |
| viv-routing | □ Designed in SPEC, not extracted | Next |
| viv-workflows | □ Designed in SPEC, not extracted | After routing |
| viv-orchestration-rules | □ Designed in SPEC, not extracted | After workflows |
| viv-hooks | □ Designed in SPEC, not extracted | Last (depends on stable contracts) |

viblocks-ai still operates with its monolithic `.claude/` setup. The migration is incremental: each extraction is paired with viblocks-ai vendoring the new repo back, replacing its in-place implementation.

## Extraction order and rationale

```
viv-skills (done)
    ↓
viv-agents (done)
    ↓
viv-routing       ← independent of workflows; only depends on agents (already done)
    ↓
viv-workflows     ← references agents (done) + routing (will be done)
    ↓
viv-orchestration-rules ← references all preceding components
    ↓
viv-hooks         ← depends on stable contracts from all preceding
```

**Why this order:**
- Skills first: the heaviest content, highest reuse value
- Agents next: declares contracts the rest will consume (`type`, `domain`, `behavior`)
- Routing third: declarative data depending only on agents
- Workflows fourth: declarative data depending on routing + agents
- Orchestration-rules fifth: behavioral docs referencing all prior
- Hooks last: code repo consuming all prior contracts

Hooks are last because their contracts depend on stable upstream contracts. Doing hooks first would mean iterating on hook code every time a downstream contract evolves.

## Per-extraction migration steps

For each remaining component (`viv-routing`, `viv-workflows`, `viv-orchestration-rules`, `viv-hooks`):

### Step 1 — Design and create the repo

- Create `viv-<component>` repo in viblocks org
- Apply the design from this SPEC (component sections + ADRs)
- Add component-specific README, ADRs, and migration notes
- Initial commit with the redesigned structure

### Step 2 — Sanitization and SOLID review

- Identify viblocks-specific content in viblocks-ai's current implementation
- Replace project-specific paths with placeholders
- Replace project-specific identifiers (`VI-XXX`, viblocks paths, hardcoded agent names) with generic equivalents or templates
- Review the redesign against the SPEC's ADRs — confirm SOLID compliance

### Step 3 — Re-vendor into viblocks-ai

- Update viblocks-ai's `.claude/` to vendor from the new repo instead of inline implementation
- Verify all hooks/data still function (existing tests pass)
- Document the version vendored in viblocks-ai's `.claude/VENDORED.md`
- Open PR in viblocks-ai for the migration; review against checklist

### Step 4 — Knowledge preservation audit

- Compare what was extracted vs. what stayed in viblocks-ai
- Confirm no domain knowledge was lost (e.g. blacklist-monitoring stays in viblocks)
- Document any losses in the component's `architecture/preservation-audit.md`

### Step 5 — Composition tier validation

- Verify the new component fits the tier model
- Update `viv-typed-agents/composition/tiers.md` if the component changes the tier matrix

## viblocks-ai-specific knowledge that stays behind

Some content in viblocks-ai is project-specific and does NOT extract:

| Content | Why it stays | Where it lives |
|---|---|---|
| `blacklist-monitoring` skill | Domain knowledge of viblocks' product | viblocks-ai/`.claude/skills/blacklist-monitoring/` |
| `services/core`, `services/bot`, `services/ui` paths | Project structure | viblocks-ai/`routing-table.json` (post-vendor, fills placeholders) |
| `VI-XXX` issue ID format | Linear integration | viblocks-ai/`workflows/audit-trail-pattern.json` (consumer-defined regex) |
| Specific agent names like `nestjs-crypto-implementer` | Pre-redesign legacy | viblocks-ai/`routing-table.json` (post-vendor uses redesigned names like `backend-crypto-implementer`) |
| `.aidlc-rule-details/` content | AI-DLC integration files | viblocks-ai/`.aidlc-rule-details/` |
| Blacklist domain detector keywords (`TronPoll`, `DetectionEnrich`, etc.) | viblocks-domain advisory | viblocks-ai/custom hook (if needed) |

## Naming migration: framework-prefix → stack-prefix

viblocks-ai currently uses framework-coupled agent names:
- `nestjs-crypto-implementer` → migrates to `backend-crypto-implementer`
- `reactjs-crypto-implementer` → migrates to `frontend-crypto-implementer`
- `nestjs-crypto-reviewer` → migrates to `backend-crypto-reviewer`
- `reactjs-crypto-reviewer` → migrates to `frontend-crypto-reviewer`

Migration applies during the viv-routing extraction (the routing-table is the central name registry).

`viblocks-ai/CLAUDE.md` and inline references must be updated when migrating to viv-orchestration-rules' template.

## Inline hooks migration

viblocks-ai has 5 hooks inline in `settings.json`:
1. Skill-install advisor
2. Post-implementation advisory (L3)
3. Semantic token gate
4. Issue-close evidence gate (L4)
5. Fix-intent debugging gate (L5)
6. Blacklist domain detector

Each becomes a separate file in `viv-hooks` (per ADR-RD-001):
- 1 → `advisory/skill-installed-advisor.sh` (generic)
- 2 → `advisory/post-impl-chain.sh` (consumes workflow rule data)
- 3 → `advisory/semantic-token-gate.sh` (parameterized via workflow rule data; viblocks-specific patterns become `viblocks-ai/workflows/semantic-token-rules.json`)
- 4 → `advisory/evidence-gate.sh` (consumes `evidence-schema.json` from workflows)
- 5 → `advisory/fix-intent-gate.sh` (consumes `fix-intent-pattern.json` from workflows)
- 6 → viblocks-ai-specific custom hook (NOT in viv-hooks; consumer-defined extension)

## Migration timeline

The migration is **opportunistic**, not deadline-driven. Each component is extracted when:
1. The design is stable in this SPEC
2. The viblocks-ai team has bandwidth for the vendor-back integration
3. A consumer (viblocks-ai or another) needs the component

There is no commitment to extract all components within a fixed time. The SPEC stands as the reference; extractions follow as needed.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Extraction breaks viblocks-ai during vendor-back | Each extraction is followed by full test suite run in viblocks-ai before merging |
| New component's design proves incorrect under real use | SPEC is versioned (semver-style); breaking changes require ADR amendment |
| Knowledge loss during sanitization | Per-extraction `preservation-audit.md` documents what was removed and why |
| Naming migration confuses viblocks-ai contributors | Migration PR includes a NAMING.md mapping old → new names; gradual rollout via routing-table aliases if needed |
