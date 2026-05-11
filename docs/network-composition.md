# Network composition reference

Authoritative diagram of how `issue-tracker-linear` fits into the wider
viblocks repo network. Mirrored in:

- `viv-typed-agents/docs/network-composition.md`
- `viblocks-aidlc-orchestrator/docs/network-composition.md`
- `issue-tracker-linear/docs/network-composition.md` (this file)

## Layered view

```
                  LAYER 4 — CONSUMER
                  ═══════════════════
                       viblocks-ai (or any other consumer)
                            │
              ┌─────────────┼─────────────────────────┐
              │             │                         │
              │ installs    │ installs                │ installs
              ▼             ▼                         ▼
       ┌─────────────┐  ┌────────────────────┐  ┌───────────────────┐
       │ typed-agts  │  │ aidlc-orchestrator │  │ issue-tracker-    │
       │ stack       │  │   (LAYER 3a)       │  │   linear          │
       │ (LAYER 2)   │  │                    │  │   (LAYER 3b)      │
       └──────┬──────┘  └────────┬───────────┘  └─────────┬─────────┘
              │                  │                        │
              │                  │ MANIFEST.yaml          │ depends on
              │                  │ pins typed-agents      │ ABSTRACTION
              │                  │ commits                │ (schema URL),
              │                  ▼                        │ no MANIFEST pin
              │           consumes rules/hooks/           │
              │           workflows/agents/etc.           │
              │                                           │
              └────────────── ABSTRACTION ────────────────┘
                       owned by typed-agents
              (viv-workflows/schemas/issue-tracker-
               adapter-contract.schema.json)
```

## Dependency taxonomy

| Type | Mechanism | Example |
|---|---|---|
| Binary pin (hard) | `MANIFEST.yaml` with commit hash | viv-typed-agents → viv-workflows@<sha> |
| Composition (medium) | `install.sh` copies files into target | aidlc-orchestrator → typed-agents stack |
| Contract reference (soft) | URL to schema/doc in another repo | issue-tracker-linear → viv-workflows schema |
| Side-by-side install (none) | Consumer installs both; they don't know each other | viblocks-ai → typed-agents + issue-tracker-linear |
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
| viblocks-aidlc-orchestrator | 3a | viv-typed-agents | Superpowers |
| **issue-tracker-linear** | 3b | — (none) | viv-workflows (contract schema) |
| viblocks-ai (consumer) | 4 | typed-agents, aidlc-orchestrator, issue-tracker-linear | — |

## Rules of thumb

1. **MANIFEST.yaml = version commitment.** Only justified when this repo
   consumes the pinned repo's artifacts at the binary/behavioral level.
2. **URL reference ≠ MANIFEST pin.** Citing an abstraction (schema, rule) by
   URL is correct DIP; it does not force pinning the implementation.
3. **Arrow direction follows control:** whoever defines the rule (high-level)
   is "upstream"; whoever implements it (low-level) is "downstream". The
   adapter is downstream of typed-agents in abstraction but independent in
   implementation.
4. **Composition is the consumer's job.** Layer 4 is not auto-composed of
   Layer 3; the consumer installs what it needs.
5. **typed-agents never knows concrete providers** (Linear, Jira, GitHub) —
   only the abstraction (the verb contract).
6. **Adapters never know typed-agents internals** — only the contract.

## Why `issue-tracker-linear` has no MANIFEST pin

`issue-tracker-linear` depends on the **abstraction** (the verb contract)
that lives at `viv-workflows/schemas/issue-tracker-adapter-contract.schema.json`,
not on typed-agents' implementation.

Pinning a typed-agents commit would couple the adapter to the entire
implementation stack — unjustified, since the adapter only needs the contract.
Citing the schema by URL is sufficient.

If the contract evolves with a breaking change, the adapter will be updated
alongside; the URL acts as the soft compatibility marker. See
`architecture/decisions/ADR-001-no-pin-to-typed-agents.md` for the SOLID
rationale.
