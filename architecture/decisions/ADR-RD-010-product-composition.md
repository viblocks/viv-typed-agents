# ADR-RD-010 — Product composition: viv-typed-agents is THE installable; sub-repos are internal SOLID decomposition

**Status:** Accepted
**Date:** 2026-05-09
**Category:** Strategic (system-wide framing)

## Context

Through extraction we produced 7 repos (1 umbrella + 6 components). Each was extracted with its own README declaring "vendor this repo into your project" — implying each was an independently consumable product. This was a natural artifact of the extraction order: skills first, then agents, etc. Each repo carried its own install instructions.

After extraction, the strategic framing crystallized:

> "typed-agents IS the product. The 6 repos are its internal SOLID decomposition, not 6 independent products."

The current artifacts contradict this:
- Each sub-repo's README implies standalone consumption.
- `composition/tiers.md` says "T1 = vendor `viv-skills`" treating tiers as which repo to vendor.
- SPEC §7 diagrams tiers as repo-subset selection.
- Goal G4 (composability) was framed as "incrementally vendor more sub-repos."

The internal SOLID decomposition (one reason to change per repo) is valuable for development hygiene — but consumers should install ONE thing, not 6.

## Decision

`viv-typed-agents` is the **installable product**. The other 6 repos are **internal versioned components** of that product, exposed publicly for transparency and surgical-use escape hatch but not advertised as installation targets.

### Composition mechanism

The product is composed via a **`MANIFEST.yaml` + `scripts/install.sh`** pattern:

- `MANIFEST.yaml` pins each component to a specific commit SHA.
- `scripts/install.sh` clones components from those SHAs and deploys to the consumer's `.claude/`.
- Tier selection (`--tier 1..5`) and component selection (`--skills`, `--agents`, `--exclude`) are flags on the installer, not separate vendor decisions.

This preserves the SOLID decomposition (the 6 repos still exist with their own ADRs) while making the consumer surface coherent (one product, one install).

### Three granularity levels (preserves G4)

| Granularity | Mechanism | Use case |
|---|---|---|
| Whole product | `install.sh --tier 5` | Standard adoption |
| Tier-configured | `install.sh --tier 1\|2\|3\|4\|5` | Incremental adoption |
| Sub-component | `install.sh --skills X --agents Y` OR `cp -r` from public sub-repo | Surgical use |

### Why not pure submodules

True git submodules (with `.gitmodules` and gitlinks) were considered but rejected at MVP:

- Submodule UX is famously painful (`--recursive` flag forgotten, detached HEAD, two-step commit).
- The `install.sh` script provides equivalent UX (single command bootstrap) without exposing submodule mechanics.
- Migration from manifest+install.sh to submodules later is straightforward (the SHAs already pinned in MANIFEST become the submodule heads).

Documented as future option; not implemented at this layer.

### Why not monorepo

Absorbing the 6 repos into typed-agents was rejected:

- Destroys the SOLID decomposition (one reason to change per repo).
- Equivalent to undoing the redesign work that produced 35 ADRs.
- Sub-component release cycles (e.g. viv-hooks security patch) become coupled to the whole product.
- Surgical-use escape hatch (cp -r single skill) requires the sub-repos to remain standalone repos.

## Rationale

| Concern | How this satisfies |
|---|---|
| Consumer simplicity | One install command; one product to upgrade |
| Reproducibility | MANIFEST pins SHAs; v1.0.0 of typed-agents == specific component versions |
| SRP at repo level | Each sub-repo retains its single reason to change |
| G4 (composability) | Three granularity levels covered |
| Reversibility | If submodules become preferred later, the manifest provides the migration path |
| ADR-RD-008 (pure descriptors) | Internal `cp -r` mechanism preserved; just abstracted behind `install.sh` |

## Consequences

### What changes in published artifacts

1. `typed-agents/README.md` leads with **install** as the primary section. Component status table reframed as "internal architecture."
2. `composition/tiers.md` reframes tiers as **installer configurations**, not "which repo to vendor."
3. `SPEC.md §7` (composition tiers) updated to reference installer flags.
4. `SPEC.md §1.1 Goal G4` updated: "incremental adoption via installer tier flag" instead of "incremental vendoring of sub-repos."
5. Each sub-repo's README gains a banner declaring it an internal component, with the typed-agents install path as canonical.

### What does NOT change

- The 6 sub-repos remain public and `cp -r`-able (escape hatch).
- Each sub-repo's ADRs and structure stay intact.
- The 35 ADRs documenting the redesign remain valid.
- ADR-RD-008 (pure descriptors) is preserved at the sub-repo level.
- Consumer-side outcome (files in `.claude/`) is identical to what manual vendoring would have produced.

### Versioning

`viv-typed-agents` adopts semver. Each release pins a tested combination of component SHAs in MANIFEST.yaml. Component repos retain their own semver independently; their versions appear in MANIFEST.

## Alternatives considered

- **Pure git submodules:** rejected (UX friction; future migration possible).
- **Subtree merge:** rejected (history conflation, source-of-truth ambiguity).
- **Monorepo (absorb 6 into typed-agents):** rejected (destroys SOLID decomposition).
- **Auto-vendor in release (commit copies):** rejected (typed-agents repo bloat; risk of in-place edits being lost on next sync).
- **Status quo (each repo standalone):** rejected (does not match product framing; consumer must orchestrate 6 vendoring steps).

## Related

- ADR-RD-008 (pure descriptors — preserved at sub-repo level)
- ADR-RD-009 (preserve viblocks objectives; redesign architecture per SOLID)
- viv-typed-agents `MANIFEST.yaml`
- viv-typed-agents `scripts/install.sh`
