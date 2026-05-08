# ADR-RD-009 — Preserve viblocks' objectives; redesign architecture per SOLID

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Strategic (system-wide framing)

## Context

This work began as "extract typed-agents from viblocks-ai into reusable repos". As the work progressed, the framing shifted: this is **not extraction, it is redesign**. The decisions we made for `viv-skills` (layered stack, domain organization) and `viv-agents` (SOLID frontmatter, stack-prefix naming, layered tier structure) were not just sanitization — they were architectural choices.

The remaining components (`viv-routing`, `viv-workflows`, `viv-hooks`, `viv-orchestration-rules`) deserve the same treatment: redesign from first principles, not preservation of viblocks' implementation choices.

This ADR formalizes the strategic framing.

## Decision

The strategy redesigns the **architecture** while preserving the **objectives**.

### What is preserved (objectives)

1. **Specialized dispatch** — typed agents replace `general-purpose` for domain-specific work
2. **Knowledge separation** — domain patterns live in skills, not agent prompts
3. **Quality enforcement** — code-quality discipline is structurally hard to bypass
4. **Audit trail** — every change to a critical path carries traceable provenance
5. **Composability** — incremental adoption from minimum to full

### What is redesigned (architecture)

1. **6 small components** instead of one monolithic `.claude/` setup
2. **Pure declarative descriptors** with a single executable code repo
3. **DIP contracts** between components (no implicit coupling)
4. **Stack/domain naming** (not framework-coupled)
5. **Single hook type per concern** (not asymmetric mode policies)
6. **Validation deferred** to deterministic point (Edit/Write time, not Agent dispatch)
7. **Workflow rules as data** (not embedded in bash)
8. **Single source of truth** for routing + classification (no separate classifier file)

### What is taken from viblocks as reference

- Inventory of concerns to address (we identified 12+ enforcement points by reading viblocks)
- Operational lessons (the marker registry exists because cwd-heuristic broke; the redesign keeps the marker)
- Skill content (the actual knowledge in `viv-skills` came from viblocks' skills, sanitized)
- Agent body content (viblocks' agent prompts informed the agent bodies, with placeholder substitution)

### What is explicitly NOT preserved

- viblocks-ai's `.claude/settings.json` structure (replaced by minimal glue + external hooks per ADR-RD-001)
- viblocks-ai's "Capa 1-8" enforcement model (replaced by 5-tier model in SPEC §3)
- viblocks-ai's `artifact-classifier.json` as a separate file (eliminated per ADR-RD-004)
- viblocks-ai's prompt-grep dispatch validation (replaced by Edit/Write-time check per ADR-RD-007)
- viblocks-ai's inline hooks in settings.json (extracted to files per ADR-RD-001)
- viblocks-ai's framework-prefix naming (`nestjs-*`, `react-*`) — replaced by stack-prefix per viv-agents ADR-012

## Rationale

The redesign is justified because:

1. **viblocks' implementation evolved organically.** Layers were added incrementally (Capa 7 added for worktree confinement, Capa 8 added for infra paths, fast-lane added for VI-130). Organic growth produces SRP violations and duplication.

2. **The strategy is for reuse.** A reusable strategy must be cleaner than the project that birthed it — otherwise consumers inherit accidental complexity.

3. **SOLID violations have measurable cost.** The duplicated `CLASS_A_PATTERNS` array in `enforce-routing.sh` mirroring `artifact-classifier.json` is exactly the kind of debt we don't want to propagate.

4. **The objectives don't depend on the architecture.** The same code-quality outcomes can be achieved with a cleaner structure.

## Consequences

- The SPEC document is the **strategy specification**, not the "viblocks extraction guide"
- ADRs document **why each redesign decision is better than viblocks' original**, with explicit reference to violations being fixed
- The migration from viblocks-ai is a **migration plan** (`migration/from-viblocks.md`), not the primary deliverable
- Other consumers (greenfield projects) can adopt the strategy without ever reading viblocks-ai

## Acknowledgments

This redesign exists because the user explicitly framed the work as redesign rather than extraction. The earlier framing produced a less rigorous analysis. Without the reframing, this strategy would have inherited viblocks' SOLID violations.

## Related

All other ADRs (RD-001 through RD-008) are concrete applications of this decision.
