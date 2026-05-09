# viv-typed-agents

**The strategy specification** for a SOLID-redesigned typed-agents architecture. Umbrella repo that documents how the six component repos (`viv-skills`, `viv-agents`, `viv-routing`, `viv-workflows`, `viv-hooks`, `viv-orchestration-rules`) compose into a coherent system for high-quality, dispatch-driven code generation with Claude Code.

This is **not** a code repo. It contains the design specification, cross-component ADRs, composition guides, and migration playbook.

## Contents

```
viv-typed-agents/
├── SPEC.md                              ← strategy + architecture + audit
├── architecture/
│   ├── solid-audit.md                   ← critique of viblocks current implementation
│   ├── component-architecture.md        ← static structure (Diagram 1)
│   ├── runtime-dispatch.md              ← dynamic behavior (Diagram 2)
│   ├── component-contracts.md           ← inter-component interfaces (DIP)
│   └── decisions/
│       ├── ADR-RD-001-no-inline-hooks.md
│       ├── ADR-RD-002-marker-redesigned.md
│       ├── ADR-RD-003-single-routing-file.md
│       ├── ADR-RD-004-classifier-folded.md
│       ├── ADR-RD-005-workflow-gates-as-data.md
│       ├── ADR-RD-006-three-hook-types.md
│       ├── ADR-RD-007-defer-validation.md
│       ├── ADR-RD-008-pure-descriptors.md
│       └── ADR-RD-009-preserve-objectives.md
├── composition/
│   └── tiers.md                         ← 5 adoption tiers (Diagram 3)
└── migration/
    └── from-viblocks.md                 ← migration plan
```

## What this redesigns

The strategy is **inspired by viblocks-ai's typed-agents implementation** but **redesigns the architecture from first principles** applying SOLID rigorously. We preserve the objectives:

- Specialized dispatch by domain (typed agents instead of generic ones)
- Knowledge content separated from agent identity
- Enforcement layered for impossibility-to-bypass on critical paths
- Audit trail and post-implementation chains for code quality

We diverge in the architecture:

- 6 small components instead of one monolithic `.claude/` setup
- Pure declarative descriptors with single executable code repo
- DIP contracts between components (no implicit coupling)
- Stack/domain naming (not framework-coupled)
- Single hook type per concern (not asymmetric mode policies)
- Validation deferred to deterministic point (Edit/Write time, not Agent dispatch)

See `SPEC.md` for the full strategy. See `architecture/solid-audit.md` for the SOLID critique that justifies each redesign decision.

## Component status

| Component | Repo | Status |
|---|---|---|
| Knowledge | [viv-skills](https://github.com/viblocks/viv-skills) | Extracted |
| Roles | [viv-agents](https://github.com/viblocks/viv-agents) | Extracted |
| Routing | [viv-routing](https://github.com/viblocks/viv-routing) | Extracted |
| Workflows | [viv-workflows](https://github.com/viblocks/viv-workflows) | Extracted |
| Enforcement | [viv-hooks](https://github.com/viblocks/viv-hooks) | Extracted |
| Behavioral | [viv-orchestration-rules](https://github.com/viblocks/viv-orchestration-rules) | Extracted |

## Adoption

This repo is the **starting point** for a new project that wants to adopt the strategy. Read `composition/tiers.md` to choose the right adoption tier (T1 to T5) based on what you need.

## License

TBD
