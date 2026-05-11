# Design — `upgrade.sh --all` and `--check`

**Date:** 2026-05-11
**Issue:** [viblocks/viv-typed-agents#11](https://github.com/viblocks/viv-typed-agents/issues/11)
**Status:** approved

## Problem

`MANIFEST.yaml` pins each component (`viv-skills`, `viv-agents`, `viv-routing`, `viv-workflows`, `viv-hooks`, `viv-orchestration-rules`) to a specific commit SHA. When upstream component repos advance, the manifest is not automatically updated, and `install.sh` silently deploys stale versions.

Current `upgrade.sh` bumps **one component at a time**. Keeping six components current requires six manual invocations plus a custom commit message, which is enough friction that drift accumulates unnoticed (4 of 6 components were behind during a fresh install on 2026-05-11).

There is no read-only way to ask "is my manifest current?" — answering requires running `git ls-remote` by hand for each component.

## Goals

1. One command keeps all components current: `./scripts/upgrade.sh --all`.
2. One command answers "is anything stale?" without side effects: `./scripts/upgrade.sh --check`.
3. CI-friendly: optional non-zero exit when drift is detected.
4. No new scripts. No new dependencies. Reuse existing SHA-resolution logic.

## Non-goals

- Modifying `install.sh` to check freshness at install time (rejected — adds network latency to every install and only fires at one moment).
- Automatic git commits. The user reviews bumps and commits manually, same as today.
- Coordinated multi-component tags (e.g. `--all --to v2.0.0`). Components release independently; cross-component refs would rarely exist and add confusion.

## Design

### New flags on `scripts/upgrade.sh`

#### `--check` (read-only)

Resolves the `main` HEAD of every component's upstream repo via `git ls-remote` and compares against the SHA pinned in `MANIFEST.yaml`. Prints a status table. Does not modify `MANIFEST.yaml`.

```
$ ./scripts/upgrade.sh --check
==> Checking 7 components against upstream main...

  COMPONENT                  PINNED     UPSTREAM   STATUS
  viv-skills                 2e40a61    b4e2e36    ⚠ behind
  viv-agents                 48d85e4    4c2bb3c    ⚠ behind
  viv-routing                f6a3e63    eecd08f    ⚠ behind
  viv-workflows              419b659    419b659    ✓ current
  viv-hooks                  534220e    7495481    ⚠ behind
  viv-orchestration-rules    336fa5d    336fa5d    ✓ current
  viv-typed-agents-setup     -          -          ⊘ self-hosted (skipped)

4 components behind, 2 current, 1 skipped.
Run `./scripts/upgrade.sh --all` to bump all behind components.
```

**Combinable with a positional component name** to check just one:
```
$ ./scripts/upgrade.sh --check viv-hooks
viv-hooks  534220e → 7495481  ⚠ behind
```

#### `--exit-code` (modifier for `--check`)

By default `--check` exits 0 regardless of drift. With `--exit-code`, exits 1 if any component is behind. Mirrors `git diff --exit-code`. Intended for CI guard scripts.

Only meaningful combined with `--check`. Combining with `--all` or default mode is a usage error.

#### `--all` (write)

Iterates all components with `repo != <self>` and bumps each to its `main` HEAD. Components already current are left untouched and reported as such. Self-hosted components (`viv-typed-agents-setup`) are skipped with a visible message.

```
$ ./scripts/upgrade.sh --all
==> Bumping all components to main HEAD...

  viv-skills:               2e40a61 → b4e2e36 ✓
  viv-agents:               48d85e4 → 4c2bb3c ✓
  viv-routing:              f6a3e63 → eecd08f ✓
  viv-workflows:            already at 419b659 (skip)
  viv-hooks:                534220e → 7495481 ✓
  viv-orchestration-rules:  already at 336fa5d (skip)
  viv-typed-agents-setup:   self-hosted (skip)

Bumped 4, already-current 2, skipped 1.
MANIFEST updated. Don't forget to:
  git add MANIFEST.yaml && git commit -m "deps: bump 4 components to latest main

  - viv-skills: 2e40a61 → b4e2e36
  - viv-agents: 48d85e4 → 4c2bb3c
  - viv-routing: f6a3e63 → eecd08f
  - viv-hooks: 534220e → 7495481"
```

`released_at` in `MANIFEST.yaml` is updated once at the end (not per-component).

### Flag compatibility matrix

| Combination | Behavior |
|---|---|
| `upgrade.sh <comp>` | Existing behavior, unchanged |
| `upgrade.sh <comp> --to <ref>` | Existing behavior, unchanged |
| `upgrade.sh --check` | Check all components, exit 0 |
| `upgrade.sh --check <comp>` | Check one component, exit 0 |
| `upgrade.sh --check --exit-code` | Check all, exit 1 if drift |
| `upgrade.sh --all` | Bump all eligible components |
| `upgrade.sh --all --to <ref>` | **Error** — multi-component refs not supported |
| `upgrade.sh --all <comp>` | **Error** — mutually exclusive |
| `upgrade.sh --check --all` | **Error** — mutually exclusive |
| `upgrade.sh --exit-code` (without `--check`) | **Error** — only valid with `--check` |

### Implementation sketch

The existing script already contains:
- YAML reader (`yq_get`, `yq_set`) with `yq` / `python+PyYAML` fallback
- Component lookup via `.components."$COMP".repo`
- SHA resolution via `git ls-remote "$REPO_URL" "$TARGET_REF"`

`--all` and `--check` need:

1. **Component enumeration** — read `.components | keys` from MANIFEST.
2. **Per-component resolve** — factor existing single-component logic into a function `resolve_component(comp_name, target_ref)` that returns `(old_sha, new_sha)` or skip reason.
3. **`--check` mode** — call resolve for each, format table, exit 0 (or 1 with `--exit-code` flag).
4. **`--all` mode** — call resolve for each, call `yq_set` for those that drifted, accumulate commit-message lines, print summary.

Self-hosted handling already exists (`if [ "$REPO_URL" = "<self>" ]`) — extend so single-component mode keeps current `exit 2` behavior, but `--all` and `--check` treat it as "skip with message".

### README changes

Add a "Keeping components current" subsection under the existing operations docs:

```markdown
### Keeping components current

Component repos advance independently. To check for drift:

    ./scripts/upgrade.sh --check

To bump everything to latest `main`:

    ./scripts/upgrade.sh --all
    git diff MANIFEST.yaml
    git commit -am "deps: bump <N> components to latest main"

To bump a single component to a specific ref (existing behavior):

    ./scripts/upgrade.sh viv-hooks --to v1.2.0

In CI, fail the build on stale manifest:

    ./scripts/upgrade.sh --check --exit-code
```

### Tests

This is the first automated test for `scripts/`. Establishes a pattern.

**Location:** `scripts/tests/upgrade.test.sh`

**Approach:** drive `upgrade.sh` against a fixture MANIFEST in a temp dir, with `git ls-remote` shimmed via a `PATH` prepend. The shim is a tiny script that maps `(repo_url, ref) → fake SHA` from a fixture table, so tests don't hit the network.

**Cases:**

1. `--check` with all components current → exit 0, table shows all ✓.
2. `--check` with 2 components behind → exit 0, table shows 2 ⚠.
3. `--check --exit-code` with drift → exit 1.
4. `--check --exit-code` without drift → exit 0.
5. `--check <comp>` checks only that component.
6. `--all` bumps drifted components, leaves current ones, skips `<self>`.
7. `--all --to <ref>` exits with usage error.
8. `--all <comp>` exits with usage error.
9. `--exit-code` without `--check` exits with usage error.
10. Existing single-component invocations still work (regression).

Tests run as `bash scripts/tests/upgrade.test.sh` and exit non-zero on any failure. No test framework dependency — same minimal-bash style as `skills/setup/tests/`.

## Risks & mitigations

- **`git ls-remote` network failure** — current single-component path already errors on this; `--all` and `--check` inherit the same failure mode (fatal). Acceptable: if the network is down, you can't update anything, full stop. The error message will name the failing component.
- **MANIFEST mid-write corruption** — `--all` does N successive `yq_set` calls. If one fails halfway, the manifest is partially updated. Mitigation: write to `MANIFEST.yaml.tmp` first, atomic rename at the end. Add this to the implementation plan.
- **Self-hosted convention** — currently only `viv-typed-agents-setup` has `repo: <self>`. If future components also use this, the skip logic generalizes correctly. No change needed.

## Out of scope

- Auto-commit / auto-PR creation.
- Hooking `--check` into a pre-commit or CI workflow file (consumers wire it up themselves).
- Validating component compatibility (e.g. "does viv-hooks SHA X work with viv-routing SHA Y?"). The current model assumes `main` of each is mutually compatible; that's a separate concern owned by component maintainers.
