# ADR-RD-004 — Eliminate artifact-classifier.json; fold into routing as enforced field

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-routing)

## Context

viblocks-ai has two declarative files:
- `routing-table.json` — path → agent assignment
- `artifact-classifier.json` — path → Class A or Class B (enforcement classification)

The two are **coupled by a manual invariant**: "Every pattern in `class_a_patterns` MUST have a typed agent entry in `routing-table.json`". This invariant is documented but enforced only by convention; nothing prevents drift.

This duplicates information across files. It also requires consumers to read both files to answer "should I enforce on this path?".

## Decision

**Eliminate `artifact-classifier.json`**. Fold its function into `routing-table.json` via the `enforced` field on each route entry.

The classification rule becomes:

```
class_a(path) := exists route in routing-table where
                 enforced == true AND
                 path matches any of route.paths
class_b(path) := !class_a(path)
```

No separate file. No invariant to maintain. The routing-table is the **single source of truth** for both routing and classification.

## Rationale

| Principle | How this satisfies |
|---|---|
| Single source of truth | One file answers both "who handles this path?" and "is this path enforced?" |
| OCP | Adding a new domain doesn't require updating two files; one entry covers both concerns |
| Drift prevention | No invariant to maintain manually; the data structure makes drift impossible |
| Consumer simplicity | One file to read, one schema to validate |

## Consequences

- `viv-routing` schema includes the required `enforced: bool` field on every route
- Hooks consume `routing-table.json` for both classification and routing decisions
- The `class_b_exclusions` mechanism from `artifact-classifier.json` is preserved differently — see "Exclusions" below

### Exclusions

`artifact-classifier.json` had `class_b_exclusions` (e.g. `services/**/README.md` is Class B even though it's under `services/**`). The redesign handles this in two ways:

1. **More specific routes win.** A consumer can add a route entry for `**/*.md` with `enforced: false` that takes precedence by being more specific than the broader `<backend-services>/**` route.
2. **Per-route exclusions:** as a future extension, a route entry can carry an `exclusions` array. For now, more-specific-route-wins is sufficient.

The matching algorithm: longest-path-match wins on conflict. Documented in `viv-routing` schema.

## Alternatives considered

- **Keep both files; add CI validator for the invariant:** rejected — solves drift but doesn't eliminate the duplication; consumers still need to read both
- **Make classifier the source; routing derived:** rejected — routing has more information (agent assignment); deriving routing from classifier loses fidelity
- **Compute classification dynamically (no `enforced` field; class A iff has implementer):** rejected — `enforced` and `implementer` are independent (a route can be enforced even with a null implementer for special cases)

## Related

- ADR-RD-003 (single routing file with field-level SRP)
- ADR-RD-007 (defer validation to Edit/Write time using this single source)
