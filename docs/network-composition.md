# Network composition reference

Authoritative diagram of how the viblocks repos compose. Mirrored across:

- `viv-typed-agents/docs/network-composition.md`
- `viblocks-aidlc-orchestrator/docs/network-composition.md`
- `issue-driven-orchestrator/docs/network-composition.md`
- `issue-tracker-linear/docs/network-composition.md`

## Responsibilities (SRP)

| Layer | Repo | Single responsibility |
|---|---|---|
| 1 | Superpowers | Skills + discipline (reference patterns) |
| 2 | viv-typed-agents (meta) | Compose dispatch components into installable product |
| 2 | viv-orchestration-rules | Dispatch rules (IRON LAW, mechanism, routing protocol, post-impl chain) |
| 2 | viv-workflows | Schemas for dispatch-enforcement contracts (audit-trail, evidence, fix-intent, pairings, chain) |
| 2 | viv-hooks | Runtime enforcement hooks |
| 2 | viv-agents | Typed agent declarations |
| 2 | viv-skills | Domain skill packs |
| 2 | viv-routing | Routing-table loader + config |
| 3 | viblocks-aidlc-orchestrator | AI-DLC change flow (Inception/Construction/Verification/Deployment) |
| 3 | issue-driven-orchestrator | Issue-driven change flow (autonomous, post-production) |
| 3 | issue-tracker-linear | Linear provider adapter (issue-tracker verb contract impl) |
| 4 | Consumer (e.g. viblocks-ai) | Application — installs whichever Layer 2/3 stacks it needs |

## Layered view

```
                  LAYER 4 — CONSUMER (e.g. viblocks-ai)
                  ════════════════════════════════════
                            │
        ┌───────────────────┼──────────────────┬──────────────────┐
        │ installs          │ installs         │ installs         │ installs
        ▼                   ▼                  ▼                  ▼
  ┌───────────────┐  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐
  │ typed-agents  │  │ aidlc-           │  │ issue-driven-│  │ issue-tracker-   │
  │ stack         │  │ orchestrator     │  │ orchestrator │  │ linear           │
  │ (Layer 2)     │  │ (Layer 3a)       │  │ (Layer 3b)   │  │ (Layer 3c)       │
  │               │  │ AI-DLC flow      │  │ Issue flow   │  │ Linear adapter   │
  └───────┬───────┘  └─────┬────────────┘  └──────┬───────┘  └─────────┬────────┘
          │                │ MANIFEST pin         │ uses (no pin)      │
          │                │ to typed-agents      │ - typed-agents     │ implements
          │                │                      │ - adapter contract │ verb contract
          │                ▼                      ▼                    │
          │           dispatches via         dispatches via             │
          │           typed-agents IRON      typed-agents IRON          │
          │           LAW + chain            LAW + chain                │
          │                                                             │
          └──────────── all callers of issue-tracker speak ◄────────────┘
                       the verb contract owned by the
                       reference adapter (issue-tracker-linear)
```

## Key boundaries

- **typed-agents owns dispatch only.** No change-flow protocols, no issue-tracker contracts.
- **Change-flow orchestrators (3a, 3b) own their flows.** Each consumes typed-agents and any adapters it needs.
- **Adapters (3c) are standalone.** They own their own contracts. Reusable by any caller speaking the verb contract.
- **The consumer composes Layer 3.** No Layer 3 repo pins another Layer 3 repo.

## Dependency taxonomy

| Type | Mechanism | Example |
|---|---|---|
| Binary pin (hard) | `MANIFEST.yaml` with commit hash | viv-typed-agents → viv-workflows@<sha> |
| Composition (medium) | `install.sh` copies files into target | aidlc-orchestrator → typed-agents stack |
| Contract reference (soft) | URL to schema/doc in another repo | issue-driven-orchestrator → issue-tracker-linear's adapter contract |
| Side-by-side install (none) | Consumer installs both; they don't know each other | viblocks-ai → typed-agents + issue-tracker-linear + issue-driven-orchestrator |
| Conceptual (none) | Named in prose without import | aidlc-orchestrator → Superpowers |

## Per-repo dependencies

| Repo | Layer | Binary pin to | Contract reference to |
|---|---|---|---|
| viv-typed-agents (meta) | 2 | viv-orchestration-rules, viv-workflows, viv-hooks, viv-agents, viv-skills, viv-routing | — |
| viv-orchestration-rules | 2 | — | viv-workflows schemas |
| viv-workflows | 2 | — | — |
| viv-hooks | 2 | — | viv-workflows, viv-routing |
| viv-agents | 2 | — | viv-routing |
| viv-skills | 2 | — | — |
| viv-routing | 2 | — | viv-workflows |
| viblocks-aidlc-orchestrator | 3a | viv-typed-agents | Superpowers; (optionally) issue-tracker contract |
| **issue-driven-orchestrator** | 3b | — | typed-agents (rules consumed conceptually); issue-tracker contract |
| **issue-tracker-linear** | 3c | — | — (owns its own contract) |
| viblocks-ai (consumer) | 4 | composes any Layer 2/3 it needs | — |

## Rules of thumb

1. **MANIFEST.yaml = version commitment.** Only justified when consuming the pinned repo's artifacts at binary level.
2. **URL reference ≠ MANIFEST pin.** Citing an abstraction by URL is correct DIP; does not force pinning the implementation.
3. **typed-agents stays pure dispatch.** Change flows, issue-trackers, SDLC stages — none of those belong inside.
4. **Adapters own their contracts** (until enough peers exist to justify a neutral contract repo).
5. **Layer 3 repos are siblings.** None pins another. Consumer composes.
6. **Layer 4 (consumer) installs whatever subset it needs.** No Layer 3 repo is mandatory.
