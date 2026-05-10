# ADR-RD-011 — Extend orchestration-rules from aidlc-orchestrator

**Status:** Accepted
**Date:** 2026-05-09
**Category:** Strategic (system-wide framing)

## Context

Through this strategy's extraction work we produced 7 repos with SOLID decomposition (ADR-RD-009), pure descriptors (ADR-RD-008), and a product composition layer (ADR-RD-010). `viv-orchestration-rules` (Tier 5) shipped initially with 5 thin playbooks — enough to define the IRON LAW + chain orchestration, but absent the operational disciplines that mature consumers need.

Independently, [`fabianyvidal/aidlc-orchestrator`](https://github.com/fabianyvidal/aidlc-orchestrator) extracted equivalent content from viblocks-ai as a single-repo Claude Code plugin and **added** disciplines viblocks-ai never had:

- Issue Analysis Discipline (Phase 1 + Phase 2 with fast-pass criteria + verbal shortcuts)
- Overconfidence Prevention (default-to-asking for clarifying questions)
- L5 Debugging Gate Grammar Contract (formal regex contract for `Root cause:`)
- Friction Reporting (consumer-vs-plugin tracker decision tree)
- Routing Table Population Protocol (post-RE + pre-dispatch moments)
- Audit-and-Logging discipline (audit.md + JSONL cross-trail invariant)
- Per-stage AI-DLC rules (~30 stage-specific files)
- Stage Structural Patterns (~34KB of cross-stage patterns)
- Adaptive Execution + Depth Levels
- Workflow Changes (mid-workflow protocol)
- Frontend Change Discipline (universal spec-driven for frontend tasks)
- Welcome Message + Terminology + Question Format Guide

These disciplines materially increase the quality of typed-agent dispatch, change flow execution, and consumer experience.

## Decision

Extract the **full** `rules/` tree from `fabianyvidal/aidlc-orchestrator` into `viv-orchestration-rules/rules/`, sanitized to align with our SOLID architecture.

> **Naming follow-up (post-extension):** the destination directory was originally named `playbooks/` (and `_common/` inside) at the moment of this ADR. After the extension landed, the directory was renamed to `rules/` (and `common/` inside) in viv-orchestration-rules commit `845062b` to match the upstream source naming and the actual content (declarative rules, not procedural playbooks).

Sanitization is mechanical and repo-wide:

| Transformation | Reason |
|---|---|
| Agent renames `nestjs-*`→`backend-*`, `reactjs-*`→`frontend-*` (with tier preservation) | viv-routing ADR-003 (stack-prefix naming) |
| Routing path `.claude/context/routing-table.json`→`.claude/routing/routing-table.json` | viv-routing convention |
| Link path renames `common/X.md`→`common/X.md`, `<phase>/X.md`→`ai-dlc/<phase>/X.md` | viv-orchestration-rules layout |
| Repo URL renames where ownership applies | Network identity |
| Architecture note injection where `.claude/context/artifact-classifier.json` is referenced | ADR-RD-004 (classifier folded) |

Local detail in `viv-orchestration-rules/architecture/decisions/ADR-004-extend-from-aidlc-orchestrator.md`.

## Rationale

| Concern | How this satisfies |
|---|---|
| Strategic completeness | The strategy now covers the full operational surface viblocks-ai operators expected, not the subset that the initial extraction shipped |
| SOLID preservation | Each extracted file has one reason to change; the per-stage decomposition follows the same SRP as the rest of the network |
| ADR-RD-008 preservation | Content stays pure descriptors (markdown only); no executable code added to `viv-orchestration-rules` |
| ADR-RD-009 preservation | We redesign rather than extract: agent names, paths, and references are sanitized to match our SOLID architecture |
| ADR-RD-010 preservation | The installer deploys the extended content the same way it always did; consumer experience is unchanged at the install boundary |
| Attribution | Source repo cited in extension README + ADR-004 local; mechanical sanitization preserves all original prose |

## Consequences

### Strategy-level changes

- `viv-orchestration-rules` grows from 5 playbooks to 69 (~25KB to ~580KB)
- Tier 5 capability is now **substantially deeper** — operational disciplines absent from viblocks-ai are first-class
- `aidlc-orchestrator` is no longer an alternative the consumer chooses between; it is upstream source content for our extension

### What does NOT change

- 6+1 component decomposition (ADR-RD-009)
- Pure descriptors pattern (ADR-RD-008)
- Product composition: typed-agents IS the installable (ADR-RD-010)
- Cross-component contracts (routing, workflows, agents)
- The 9 prior cross-component ADRs (RD-001..RD-009)

### Operational

- `MANIFEST.yaml` bumps `viv-orchestration-rules` SHA to the post-extension commit
- `scripts/install.sh --tier 5` deploys the extended content automatically
- Consumers upgrading from prior MANIFEST get the extension on next `./scripts/upgrade.sh viv-orchestration-rules`

## Relationship to aidlc-orchestrator going forward

`fabianyvidal/aidlc-orchestrator` remains a parallel implementation with different distribution model (CC plugin vs. our installer). Future improvements published there can be back-ported via the same sanitization process. `viv-typed-agents` is the **canonical product** for our network; aidlc-orchestrator is **upstream source material**.

## Alternatives considered

- **Reference aidlc-orchestrator as external dependency**: rejected — couples our network to a third-party plugin's distribution model and identity
- **Adopt aidlc-orchestrator structure verbatim** (single-repo plugin): rejected — undoes ADR-RD-009 (SOLID decomposition) and ADR-RD-010 (product composition)
- **Bring only the AI-DLC + SP integration files, skip operational disciplines**: rejected — the operational disciplines are the highest-value differentiator vs viblocks-ai

## Related

- ADR-RD-008 (pure descriptors — preserved)
- ADR-RD-009 (preserve objectives, redesign per SOLID — extension respects this)
- ADR-RD-010 (product composition — extension flows through installer)
- viv-orchestration-rules ADR-004 (extraction execution detail)
- viv-routing ADR-003 (stack-prefix naming — applied during sanitization)
