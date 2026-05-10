# ADR-RD-012 — Separate aidlc-orchestrator from typed-agents (DIP)

**Status:** Accepted
**Date:** 2026-05-09
**Category:** Strategic (system-wide framing)

**Supersedes:** [ADR-RD-011](ADR-RD-011-extend-from-aidlc-orchestrator.md) (the prior "extend orchestration-rules" decision)

## Context

[ADR-RD-011](ADR-RD-011-extend-from-aidlc-orchestrator.md) extended `viv-orchestration-rules` with the full content of `fabianyvidal/aidlc-orchestrator` — 64 files covering AI-DLC stages, workflow disciplines, SP integration, and consumer-experience rules.

Post-extension SOLID review identified a structural violation: **two abstractions were merged into one repo**.

```
viv-typed-agents = "the dispatch system with quality enforcement"
   - razón de cambio: typed-agent dispatch policy evolves

AI-DLC = "the SDLC orchestrator that USES typed-agents at codegen"
   - razón de cambio: SDLC workflow + disciplines evolve
```

By placing AI-DLC content inside `viv-orchestration-rules`:

1. **SRP violation** — viv-orchestration-rules now had two reasons to change
2. **DIP inversion** — typed-agents (low-level) was carrying AI-DLC (high-level) content; the natural dependency direction is reversed
3. **ISP violation** — a consumer wanting only typed-agents was forced to vendor 60+ AI-DLC files
4. **OCP violation** — adding a new AI-DLC stage required modifying viv-orchestration-rules even though typed-agents wasn't changing

## Decision

Split the AI-DLC content out of `viv-orchestration-rules` into a separate repository [`viblocks/aidlc-orchestrator`](https://github.com/viblocks/aidlc-orchestrator).

**Dependency direction:**

```
aidlc-orchestrator (high-level workflow) ──depends on──> viv-typed-agents (low-level dispatch)
```

- `aidlc-orchestrator` references typed-agents IRON LAW, routing-table schema, post-impl chain rule, hook enforcement
- `viv-typed-agents` has **zero knowledge** of `aidlc-orchestrator`; it remains independently usable

### What stays in `viv-orchestration-rules`

Typed-agents-core orchestration (~10 files in `rules/common/` plus 5 entry points):

- `dispatch-protocol.md`, `post-implementation-chain.md`, `issue-driven-flow.md` (entry points)
- `ai-dlc-integration.md`, `superpowers-integration.md` (now thin pointers to aidlc-orchestrator)
- `rules/common/iron-law.md`, `typed-agent-mechanism.md`, `subagent-dispatch-contract.md`
- `rules/common/post-implementation-chain.md`, `routing-table-population-protocol.md`
- `rules/common/code-quality-rules.md`, `debugging-gate.md`, `enforcement-architecture.md`
- `rules/common/git-workflow.md`

### What moves to `aidlc-orchestrator`

- All `rules/ai-dlc/<phase>/` per-stage rules (~31 files)
- AI-DLC workflow disciplines (`adaptive-execution`, `depth-levels`, `workflow-changes`, `stage-structural-patterns`, `process-overview`)
- AI-DLC consumer experience (`welcome-message`, `aidlc-docs-structure`, `audit-and-logging`, `session-continuity`, `terminology`)
- AI-DLC artifact conventions (`content-validation`, `ascii-diagram-standards`, `question-format-guide`, `error-handling`)
- AI-DLC quality disciplines (`overconfidence-prevention`, `friction-reporting`, `frontend-change-discipline`)
- Comprehensive SP integration matrix (`superpowers-integration`, `sp-precedence`)
- AI-DLC change flow (`core-change-flow-protocol` — F1-F4 path detail)
- Opt-in extensions (`extensions/security/baseline/`, `extensions/testing/property-based/`)

## Rationale

| Concern | How DIP separation satisfies |
|---|---|
| **SRP** | Each repo has one reason to change |
| **DIP** | High-level (AI-DLC) depends on low-level (typed-agents); not the inverse |
| **ISP** | Consumer can adopt typed-agents without AI-DLC content |
| **OCP** | Adding AI-DLC stages doesn't touch typed-agents repos |
| **Reuse** | typed-agents reusable across orchestrators (AI-DLC, but also other workflow frameworks not yet built) |

## Consequences

### What changes

- New repo published: [`viblocks/aidlc-orchestrator`](https://github.com/viblocks/aidlc-orchestrator)
- `viv-orchestration-rules` slims back from 69 files to ~15 files
- `viv-orchestration-rules/rules/ai-dlc-integration.md` becomes a thin pointer to aidlc-orchestrator
- `viv-orchestration-rules/rules/superpowers-integration.md` becomes typed-agents-only; AI-DLC matrix points to aidlc-orchestrator
- `MANIFEST.yaml` viv-orchestration-rules SHA bumped to the post-trim commit
- `aidlc-orchestrator` adopts typed-agents as a declared dependency in its README + ADR-001 local

### What does NOT change

- Stripped-down typed-agents-core orchestration is still functional standalone
- 6+1 typed-agents network (skills, agents, routing, workflows, hooks, orchestration-rules + umbrella) intact
- ADR-RD-008 (pure descriptors) preserved
- ADR-RD-009 (preserve viblocks objectives, redesign per SOLID) reaffirmed
- ADR-RD-010 (typed-agents IS the installable) preserved at the typed-agents level
- Cross-component contracts (routing schema, workflow rule schemas, agent frontmatter) unchanged

### Migration path for existing consumers

A consumer who installed prior to this split has the AI-DLC content inside their `.claude/orchestration/rules/`. After this split:

1. Re-run installer: deploys only typed-agents-core orchestration to `.claude/orchestration/rules/`
2. Add AI-DLC if needed: `cp -r aidlc-orchestrator/rules /path/to/proj/.aidlc-rule-details/`
3. Old extended files (in `.claude/orchestration/rules/ai-dlc/`, `_common/` for AI-DLC content) can be deleted or kept stale; the installer doesn't manage them

### ADR-RD-011 status

Superseded by this ADR. RD-011 documented the extension; RD-012 documents the architectural correction. RD-011 remains in the history for archaeology but is no longer the current strategy.

## Alternatives considered

- **Keep extended `viv-orchestration-rules`**: rejected — SOLID violation acknowledged
- **Delete the AI-DLC content** (revert to pre-extension state): rejected — the extracted content has real value; just belongs in a different home
- **Make typed-agents depend on AI-DLC**: rejected — inverts the natural dependency direction; typed-agents must be usable without AI-DLC
- **Put AI-DLC content under `viv-typed-agents/optional/`**: rejected — co-locates two abstractions in one repo; partial fix

## Related

- ADR-RD-009 (preserve viblocks objectives, redesign per SOLID) — DIP is the SOLID-correct call here
- ADR-RD-010 (product composition) — typed-agents stays self-contained installable
- ADR-RD-011 (initial extension) — superseded by this
- aidlc-orchestrator ADR-001 (declares dependency on typed-agents)
- viv-orchestration-rules ADR-004 — trimmed in coordination
