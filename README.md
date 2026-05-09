# viv-typed-agents

**The typed-agents strategy product.** A SOLID-designed enforcement and dispatch system for Claude Code that turns generic LLM dispatch into domain-specialized typed agents with structural code-quality gates.

This is **the installable** — vendor this repo into your project and run the installer. The 6 internal components (`viv-skills`, `viv-agents`, `viv-routing`, `viv-workflows`, `viv-hooks`, `viv-orchestration-rules`) are exposed publicly for transparency and surgical use, but the recommended adoption path is via this repo's installer (per [ADR-RD-010](architecture/decisions/ADR-RD-010-product-composition.md)).

## Install

```bash
git clone https://github.com/viblocks/viv-typed-agents
cd viv-typed-agents
./scripts/install.sh /path/to/your-project --tier 5
```

Or one-liner (without local clone):

```bash
curl -sL https://raw.githubusercontent.com/viblocks/viv-typed-agents/main/scripts/install.sh \
  | bash -s -- /path/to/your-project --tier 5
```

### Tier selection

| Tier | What you get | Best for |
|---|---|---|
| 1 | Skills (knowledge content) | Solo dev, occasional Claude Code use |
| 2 | + Agents (typed dispatch behaviorally) | Small team, single-domain projects |
| 3 | + Routing + Workflows (declarative orchestration) | Multi-domain projects |
| 4 | + Hooks (structural hard-deny enforcement) | Production with quality/security needs |
| 5 | + Orchestration rules (full system, autonomous flow) | Mature projects with full automation |

```bash
# Tier 1 — just skills
./scripts/install.sh ~/my-project --tier 1

# Tier 5 — full system (default)
./scripts/install.sh ~/my-project --tier 5
```

### Granular component or skill selection

```bash
# Just one skill
./scripts/install.sh ~/my-project --skills crypto-backend

# Multiple skills + specific agents
./scripts/install.sh ~/my-project \
  --skills crypto-backend,nestjs-backend \
  --agents backend-crypto-implementer,backend-crypto-reviewer

# Tier 4 without orchestration-rules
./scripts/install.sh ~/my-project --tier 4 --exclude viv-orchestration-rules
```

See `scripts/install.sh --help` for full flag reference.

## What you get post-install

```
your-project/
└── .claude/
    ├── skills/                      ← knowledge patterns (T1+)
    ├── agents/                      ← typed agent declarations (T2+)
    ├── routing/                     ← path-to-agent map (T3+)
    ├── workflows/                   ← gate rule data (T3+)
    ├── hooks/                       ← structural enforcement (T4+)
    │   ├── deny/ advisory/ refinement/ lifecycle/ commit/
    │   ├── lib/
    │   └── settings.json.fragment
    └── orchestration/               ← CLAUDE.md template + playbooks (T5)
```

Next steps after install are printed by the installer (configure routing-table.json, glue settings.json, adapt CLAUDE.md).

## Upgrade

```bash
# Bump a single component to its latest main HEAD
./scripts/upgrade.sh viv-skills

# Bump to a specific SHA or branch
./scripts/upgrade.sh viv-hooks --to 99c56f8
```

## What's inside

This repo is the umbrella + the installer. The actual content lives in 6 internal component repos pinned in `MANIFEST.yaml`.

```
viv-typed-agents/
├── README.md                                    ← you are here
├── SPEC.md                                      ← strategy specification
├── MANIFEST.yaml                                ← pinned component SHAs
├── scripts/
│   ├── install.sh                               ← deploy product to a consumer project
│   └── upgrade.sh                               ← bump component SHAs
├── architecture/
│   ├── solid-audit.md                           ← SOLID critique of viblocks original
│   └── decisions/                               ← 10 cross-component ADRs (RD-001..RD-010)
├── composition/
│   └── tiers.md                                 ← 5 adoption tiers detailed
└── migration/
    └── from-viblocks.md                         ← migration history
```

## Internal component architecture (SOLID decomposition)

The product is composed of 6 internal repos, each with a single reason to change:

| Component | Internal repo | Role | Tiers |
|---|---|---|---|
| Knowledge | [viv-skills](https://github.com/viblocks/viv-skills) | Domain patterns + anti-patterns | 1+ |
| Roles | [viv-agents](https://github.com/viblocks/viv-agents) | Typed agent declarations | 2+ |
| Routing | [viv-routing](https://github.com/viblocks/viv-routing) | Path → agent + Class A/B classification | 3+ |
| Workflows | [viv-workflows](https://github.com/viblocks/viv-workflows) | Gate rule data | 3+ |
| Enforcement | [viv-hooks](https://github.com/viblocks/viv-hooks) | Structural hooks | 4+ |
| Behavioral | [viv-orchestration-rules](https://github.com/viblocks/viv-orchestration-rules) | CLAUDE.md template + playbooks | 5 |

The internal repos are **not advertised as installation targets** — install this product instead. They are kept public for transparency, contribution, and surgical-use escape hatch (`cp -r` a single skill if you don't need the rest).

## What this redesigns

The strategy is **inspired by viblocks-ai's typed-agents implementation** but **redesigns the architecture** applying SOLID rigorously. Preserved objectives:

- Specialized dispatch by domain (typed agents instead of generic ones)
- Knowledge content separated from agent identity
- Enforcement layered for impossibility-to-bypass on critical paths
- Audit trail and post-implementation chains

Architectural divergences:

- 6 internal components with one reason to change each (not monolithic `.claude/`)
- Pure declarative descriptors with a single executable code repo (viv-hooks)
- DIP contracts between components (no implicit coupling)
- Stack/domain naming (not framework-coupled)
- Single hook type per concern (not asymmetric mode policies)
- Validation deferred to deterministic point (Edit/Write time, not Agent dispatch)
- Single product surface: typed-agents (not 6 vendoring decisions)

See `SPEC.md` for the full strategy and `architecture/solid-audit.md` for the SOLID critique.

## License

TBD
