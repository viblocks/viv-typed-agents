# ADR-RD-006 — Three explicit hook types: deny, advisory, refinement (plus lifecycle)

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-hooks)

## Context

viblocks-ai's hooks honor an `AIDLC_ENFORCEMENT_MODE` env var with three values: `disabled`, `warn`, `hard` (default). The policy is **asymmetric**:

- `disabled` → all hooks bypass
- `warn` → fast-lane and bash-commit hooks emit advisory but allow; **hard-deny hooks ignore `warn`** (intentional — would silently downgrade hard enforcement)
- `hard` → all hooks enforce

This asymmetry is documented but not typed. A reader of `enforce-routing.sh` cannot tell from the code whether it should honor `warn`. The policy lives in implicit convention.

This is an SRP violation: the hook code mixes "what to enforce" with "how to handle modes". A reviewer can't tell at a glance which hooks are deny vs. advisory.

## Decision

Hooks have an **explicit type** declared via filename convention or metadata header. Four types:

| Type | Purpose | Honors `disabled` | Honors `warn` |
|---|---|---|---|
| **deny** | Hard block on contract violation | yes | **no** (would silently downgrade) |
| **advisory** | Warn but allow; injects `additionalContext` to inform | yes | yes |
| **refinement** | Positive override (allow what deny would block, e.g. fast-lane) | yes | yes |
| **lifecycle** | State management; no allow/deny decision | **no** (always runs to maintain state correctness) | n/a |

Filename convention:

```
viv-hooks/hooks/
├── deny/
│   ├── enforce-routing.sh
│   ├── enforce-secrets.sh
│   ├── enforce-self-mod.sh
│   ├── enforce-isolation.sh
│   └── commit-trailer-gate.sh
├── advisory/
│   ├── post-impl-chain.sh
│   ├── evidence-gate.sh
│   ├── fix-intent-gate.sh
│   └── skill-installed-advisor.sh
├── refinement/
│   └── fast-lane.sh
└── lifecycle/
    ├── pretool-agent-register.sh
    └── posttool-agent-cleanup.sh
```

Each hook's first line includes a metadata comment:

```bash
#!/usr/bin/env bash
# HOOK_TYPE: deny
# CONCERN: typed-agent dispatch for Class A paths
```

Tooling can grep `HOOK_TYPE:` to validate every hook declares its type and that the directory matches the declaration.

## Rationale

| Principle | How this satisfies |
|---|---|
| SRP | Each hook type has one mode policy; reading the type tells you the policy |
| OCP | New hooks declare their type; the runtime contract for each type is stable |
| DIP | Mode handling becomes a contract (per-type), not a per-hook implementation detail |
| Reviewability | A code review can validate "this hook is in deny/, so it must NOT honor warn" via static check |

## Consequences

- `viv-hooks` ships hooks organized by type
- A linter checks every hook has `HOOK_TYPE:` comment matching its directory
- `settings.json` template registers hooks by their type-aware file paths
- The mode-honoring logic is **shared library code** (`lib/mode-policy.sh`), invoked at hook entry

## Alternatives considered

- **Status quo (asymmetric warn policy, no types):** rejected — implicit policy invites bugs; mode behavior depends on which hook the developer happened to read
- **Single mode policy honored uniformly:** rejected — `warn` honored by deny hooks would be silent downgrade, dangerous
- **Type declared via env var only:** rejected — runtime declaration; can't be statically validated

## Related

- ADR-RD-001 (external hook files; this decision builds on that — types only meaningful if hooks are files)
- ADR-RD-005 (workflow rules as data; advisory hooks consume those rules)
