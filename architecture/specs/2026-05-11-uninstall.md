# Design — Uninstall flow for `viv-typed-agents`

**Date:** 2026-05-11
**Status:** Draft (pending implementation plan)
**Owner:** viv-typed-agents

## Problem

`viv-typed-agents` ships `install.sh` (deploys components to a consumer project) and `upgrade.sh` (bumps pinned SHAs), but no uninstaller. Users who want to remove typed-agents from a project must do it manually:

1. Identify which directories under `.claude/` came from the install
2. `rm -rf` them carefully (avoiding any user-added skills/agents/hooks)
3. Reverse the wizard's merge into `.claude/settings.json` (remove typed-agents hook entries, preserve user keys)
4. Remove the managed block from `CLAUDE.md` between the `<!-- viv-typed-agents:BEGIN/END -->` markers
5. Clean up transient state (`.subagent-active.json` etc.)

This is error-prone and the burden falls on the user every time. A turnkey installer needs a symmetric turnkey uninstaller.

## Goal

Provide a `scripts/uninstall.sh` that removes a typed-agents installation cleanly from a consumer project, preserving the user's pre-existing content (custom skills, agents, hooks, CLAUDE.md content) and the user's keys in `settings.json`.

## Non-goals

- Restore the project to its exact pre-install state. We undo only what install + wizard added; we do not snapshot file metadata or content.
- Automated backup. Users who want a safety net can `git status` / `git checkout` (most projects are in git) or use `--dry-run` to preview.
- Granularity beyond `--components`. Tier-based selective uninstall and `--exclude` are ambiguous in uninstall semantics and are not added.
- Concurrent uninstall safety. Document "don't run two uninstalls in parallel".

## User experience

```
$ ./scripts/uninstall.sh ~/my-project

Uninstall plan for /Users/.../my-project:

Directories and files to remove:
  ✗ .claude/skills/backend/                         (viv-skills)
  ✗ .claude/skills/frontend/                        (viv-skills)
  ✗ .claude/skills/devops/                          (viv-skills)
  ✗ .claude/skills/setup/                           (viv-typed-agents-setup)
  ✗ .claude/agents/backend-implementer.md           (viv-agents)
  ✗ .claude/agents/backend-crypto-implementer.md    (viv-agents)
  ...
  ✗ .claude/lib/                                    (viv-hooks)

Config changes:
  ⟲ .claude/settings.json                           (remove 9 hook entries; preserve user keys)
  ⟲ CLAUDE.md                                       (remove managed block; preserve content outside)

Transient state:
  ✗ .claude/.subagent-active.json
  ✗ .claude/.subagent-active.json.lock

Manifest:
  ✗ .claude/.install-manifest.json                  (after full uninstall)

Proceeding...
  ✓ removed 47 paths
  ✓ settings.json: 9 hook entries removed, 2 user keys preserved
  ✓ CLAUDE.md: managed block removed (12 lines above markers preserved)

Uninstall complete.
```

`--dry-run` prints the plan and exits 0 without acting. `--components <list>` filters to specific components. `--keep-config` skips settings.json + CLAUDE.md changes.

## Design

### Architecture

```
viv-typed-agents/
├── scripts/
│   ├── install.sh                       ← MODIFIED: writes .install-manifest.json
│   ├── upgrade.sh                       ← unchanged
│   └── uninstall.sh                     ← NEW: orchestrator
└── skills/setup/
    └── lib/
        ├── adapt-claude-md.sh           ← unchanged
        ├── merge-settings.sh            ← unchanged
        ├── unmark-claude-md.sh          ← NEW: remove managed block
        └── unmerge-settings.sh          ← NEW: reverse-merge from fragment
```

### Two-PR delivery

The uninstaller depends on a manifest written by install.sh. The work splits into:

- **PR-1: Install manifest.** Modify `install.sh` to emit `<target>/.claude/.install-manifest.json` capturing exactly which paths were deployed (per component). Required first because the uninstaller's correctness depends on this contract.
- **PR-2: Uninstaller.** Add `scripts/uninstall.sh` plus the two new lib scripts. Reads the manifest written by PR-1.

PR-1 is independently useful (introspection, debugging, future tooling). PR-2 is the user-visible feature.

### CLI surface (uninstall.sh)

```
./scripts/uninstall.sh <target-project-path> [options]

Options:
  --components <list>    Comma-separated component names to remove.
                         Default: all components in the install manifest.
  --dry-run              Print plan without removing anything.
  --keep-config          On full uninstall, skip the settings.json reverse-merge
                         and CLAUDE.md unmarking; only remove deployed
                         directories/files. (Partial uninstall already skips
                         these by default, so this flag is a no-op there.)
  -h | --help            Show usage.
```

**Exit codes:**
- `0` — uninstall complete, dry-run complete, or nothing to do.
- `1` — operational error (permission denied, corrupt manifest, etc.).
- `2` — input error (target not a directory, unknown component, etc.).

### `.install-manifest.json` format (PR-1)

```json
{
  "schema_version": "1.0",
  "installed_at": "2026-05-11T04:30:00Z",
  "tier": 5,
  "components": {
    "viv-skills": {
      "commit": "2e40a61",
      "paths": [
        ".claude/skills/backend/",
        ".claude/skills/frontend/",
        ".claude/skills/devops/",
        ".claude/skills/security/",
        ".claude/skills/testing/",
        ".claude/skills/discipline/"
      ]
    },
    "viv-agents": {
      "commit": "48d85e4",
      "paths": [
        ".claude/agents/backend-implementer.md",
        ".claude/agents/backend-crypto-implementer.md",
        ".claude/agents/backend-reviewer.md",
        ".claude/agents/_shared/"
      ]
    },
    "viv-routing": {
      "commit": "f6a3e63",
      "paths": [
        ".claude/routing/NAMING.md",
        ".claude/routing/README.md",
        ".claude/routing/routing-table.json",
        ".claude/routing/schema/"
      ]
    },
    "viv-hooks": {
      "commit": "534220e",
      "paths": [
        ".claude/hooks/deny/",
        ".claude/hooks/advisory/",
        ".claude/hooks/refinement/",
        ".claude/hooks/lifecycle/",
        ".claude/hooks/commit/",
        ".claude/hooks/settings.json.fragment",
        ".claude/lib/"
      ]
    },
    "viv-orchestration-rules": {
      "commit": "336fa5d",
      "paths": [
        ".claude/orchestration/rules/",
        ".claude/orchestration/CLAUDE.template.md",
        ".claude/orchestration/README.md"
      ]
    },
    "viv-typed-agents-setup": {
      "commit": "<self>",
      "paths": [".claude/skills/setup/"]
    }
  }
}
```

The `paths` array contains both files (when they correspond to specific files in the source) and directories (when they correspond to subdirectories the component owns). The uninstaller treats both via the same removal logic (`rm -rf` is safe for both).

**Granularity rule:** entries are the **top-level subdirectories and files** that the component places under its `target_path`, NOT the `target_path` itself, and NOT individual leaf files inside owned subdirs.

This matters when the `target_path` is a shared namespace (e.g., `.claude/skills/` is also where a user might add `.claude/skills/my-team-skill/`):

- ✓ Manifest entry `.claude/skills/backend/` — uninstall removes the whole `backend/` subtree, owned by viv-skills.
- ✗ Manifest entry `.claude/skills/` — uninstall would also remove the user's `my-team-skill/`. **Violates the design promise.**
- ✗ Manifest entry `.claude/skills/backend/nestjs-backend/SKILL.md` — over-granular. Inflates the manifest without benefit; viv-skills owns the whole `backend/` namespace.

For `target_path` directories that the component owns exclusively (e.g., `.claude/routing/`, `.claude/hooks/`, `.claude/orchestration/`), entries list the items directly under the target_path. Users are not expected to mix content into these namespaces; if they do, the items they added stay (e.g., a `.claude/routing/custom-notes.md` that the user dropped in is not in the manifest, so it survives uninstall).

**Capture mechanism in install.sh:** drive the manifest from the **source side**, not the destination side. For each component, after the clone (or for `<self>` components after locating `source_path`), enumerate the entries at the SOURCE that the deploy logic will copy (typically every top-level item in the source repo, modulo special-case filters like `viv-hooks` extracting `hooks/` and `lib/` separately). Map each source entry to its destination path under `<target>`. Append those destination paths (relative to `<target>`) to an in-memory array keyed by component name. Do the copy. Move on.

This is robust to **re-install on top of an existing install**: source enumeration always reports the truth of what the component owns, independent of whether the destination already had those entries from a prior run. A destination-diff approach (compare `ls` before vs. after copy) would miss entries during re-install because they already existed at the destination — causing the manifest to omit them, and a future uninstall to leak them.

After all components are processed, serialize the array to `<target>/.claude/.install-manifest.json`. The special handling for `viv-hooks` (which deploys both `.claude/hooks/` and `.claude/lib/` as separate top-level destinations) is captured naturally because both destinations are computed and registered.

### Uninstall algorithm

```
Step 0 — Validate
  - $TARGET exists and is a directory
  - $TARGET/.claude/ exists (else warn + exit 0, nothing to do)
  - $TARGET/.claude/.install-manifest.json exists and parses as valid JSON

Step 1 — Resolve component selection
  - Default: all components in the manifest
  - With --components <csv>: filter; warn on unknown components

Step 2 — Snapshot the settings.json fragment to tmp (before any removal)
  - If $TARGET/.claude/hooks/settings.json.fragment exists, cp to a tmp file
  - This snapshot is used in step 5; the original will be removed in step 4

Step 3 — Determine whether this is a full or partial uninstall
  - "Full" = no --components given, OR --components covers every entry
    in the manifest (set equality)
  - "Partial" = --components given AND covers a strict subset
  - The wizard outputs (settings.json reverse-merge, CLAUDE.md unmark)
    are operations at the installation level, not at the component level.
    They run ONLY in the full case. Partial uninstall leaves them alone.

Step 4 — Build and print the plan
  - For each selected component, list its paths from the manifest
  - If full uninstall AND NOT --keep-config:
    - List settings.json reverse-merge (with hook entry count from snapshot)
    - List CLAUDE.md unmark (if markers present)
  - List transient state files to remove (.subagent-active.json[.lock])
  - List manifest file removal if full; otherwise rewrite manifest

Step 5 — Execute (skipped if --dry-run)
  - For each path in selected components: rm -rf <path> (logged with
    file vs. directory type in the message)
  - Stop and abort on permission errors; do not continue partial removal

Step 6 — Reverse-merge settings.json
  - Skipped if: partial uninstall, --keep-config, or snapshot missing
  - Else: lib/unmerge-settings.sh $TARGET/.claude/settings.json <tmp-snapshot>

Step 7 — Unmark CLAUDE.md
  - Skipped if: partial uninstall, --keep-config, or no markers in CLAUDE.md
  - Else: lib/unmark-claude-md.sh $TARGET/CLAUDE.md

Step 8 — Remove transient state
  - rm -f $TARGET/.claude/.subagent-active.json
  - rm -f $TARGET/.claude/.subagent-active.json.lock

Step 9 — Update or remove manifest
  - If full uninstall: rm -f $TARGET/.claude/.install-manifest.json
  - If partial: rewrite manifest with remaining components

Step 10 — Cleanup
  - rm -f the tmp snapshot
  - Walk $TARGET/.claude/ bottom-up and rmdir any empty directories
    (find $TARGET/.claude -type d -empty -delete). This collapses
    intermediate empty namespaces like .claude/skills/ when all its
    typed-agents subdirs were removed AND the user has no custom skills.
  - If $TARGET/.claude/ itself was removed by the previous step (no
    content left at all), we're done. Otherwise some user content remains.
  - Print summary
```

**Critical: order of operations.**

1. The fragment is snapshotted in step 2 (before removal in step 5) so the reverse-merge in step 6 still works. Without the snapshot, removing `.claude/hooks/` deletes the fragment that step 6 needs.

2. Wizard outputs (`settings.json` reverse-merge, `CLAUDE.md` unmark) are full-install operations, not per-component. Running them on a partial uninstall would orphan typed-agents in an inconsistent state (e.g., removing `viv-skills` but reverse-merging `settings.json` would erase the hook entries for `viv-hooks` that is still installed). Step 3 makes this distinction explicit.

### Lib scripts

#### `lib/unmerge-settings.sh`

**Contract:** `unmerge-settings.sh <consumer-settings> <fragment>` removes from `<consumer-settings>` all entries that match `<fragment>`. Preserves all other content (theme, env, user-added hooks). Idempotent.

Implementation: `jq` recursive set-difference. Arrays: keep elements not in fragment; if array empty after, delete the key. Objects: recurse; if object empty after, delete the key. Scalars: untouched. If the resulting top-level object is `{}`, delete the file.

#### `lib/unmark-claude-md.sh`

**Contract:** `unmark-claude-md.sh <claude-md-path> [--remove-if-empty]` removes lines between `<!-- viv-typed-agents:BEGIN -->` and `<!-- viv-typed-agents:END -->` (inclusive of the markers themselves). Preserves all content outside the markers. Strips trailing blank lines left by the removal. Idempotent.

`--remove-if-empty`: if the file is whitespace-only after removal, delete it. Default: preserve (CLAUDE.md is user-owned).

### Error handling

| Scenario | Behavior |
|---|---|
| `.install-manifest.json` missing | Abort with clear message pointing to git-based manual cleanup. No `--legacy` fallback. Exit 2. |
| `.install-manifest.json` corrupt | Abort with path. Exit 1. |
| Path in manifest already removed by user | Log `(already removed)`, skip. Not an error. |
| `--components <name>` not in manifest | Warn and skip. Continue with others. |
| Permission denied during removal | Abort immediately. Do not leave the project in a partially-removed state without explicit feedback. Exit 1. |
| `settings.json` exists but fragment snapshot missing | Skip reverse-merge with warning: "fragment not captured; review settings.json manually". |
| `CLAUDE.md` has no markers | Skip unmark with informative log. Not an error. |
| Re-running uninstall after partial completion | Idempotent: missing paths are skipped, manifest reflects current state. |

### What is intentionally NOT done

- **No `--legacy` flag.** A flag that re-introduces the "rm -rf user customizations" risk would defeat the design. Pre-manifest installs (only 1 exists at design time: blacklist-monitor) are handled via the documented manual path (git revert or manual cleanup).
- **No backup.** Most projects are in git; `git status` + `git checkout` is the rollback. For non-git projects, `--dry-run` is the preview. Automated tarballs create the illusion of safety and clutter the consumer.
- **No `--force`.** Permission errors abort; that's the only "force" scenario, and the right answer is "fix the permission, not bypass it".
- **No tier-based filter.** `--tier N` is ambiguous: does it mean "remove components in tier N" or "leave installation at tier N"? Inverse semantics confuse. `--components` covers the legitimate use case (downgrade by removing specific components).

## Testing

### Unit-level smoke tests for new lib scripts

Append assertions to `skills/setup/tests/smoke.test.sh`:

- `unmerge-settings.sh`:
  - User keys preserved across reverse-merge
  - User-added hooks (not in fragment) preserved
  - Idempotency: re-run produces same result (md5)
  - Empty `{}` after unmerge → file deleted

- `unmark-claude-md.sh`:
  - Content above and below markers preserved
  - Managed block removed (including markers themselves)
  - Idempotency: re-run on clean file is no-op
  - `--remove-if-empty`: whitespace-only file removed

### E2E test for the round-trip

New file `skills/setup/tests/uninstall.test.sh`:

1. Create a tmp consumer project
2. Plant user-owned content (custom CLAUDE.md, custom skill at `.claude/skills/my-team-skill/`, hand-added entry in settings.json after install)
3. Run `install.sh` against it (tier 5)
4. Assert `.install-manifest.json` exists and includes the special-case paths (`viv-hooks` lists both `.claude/hooks/` and `.claude/lib/`; `viv-agents` lists flat `.md` files)
5. Run `uninstall.sh` against it (full uninstall, default flags)
6. Assert post-uninstall state:
   - typed-agents directories gone
   - user content preserved (custom skill still there, original CLAUDE.md content preserved, user's hand-added settings.json entry preserved)
   - `.install-manifest.json` removed
   - `.claude/` removed entirely (since user's custom skill was at a higher path that should still exist — verify the right thing)

### Partial-uninstall e2e

Same file, second test case:

1. Same setup as above + install
2. Run `uninstall.sh --components viv-skills`
3. Assert: viv-skills paths gone, viv-hooks/orchestration/etc. still present, settings.json UNCHANGED (no reverse-merge on partial), CLAUDE.md UNCHANGED (no unmark on partial), `.install-manifest.json` updated to reflect remaining components

## Out of scope (deferred)

- Restore-from-backup workflow (no automatic backup ships).
- Cross-version manifest migration (`schema_version: "1.0"` is locked; future versions handled with explicit migration step if needed).
- `--quiet` mode (current output is bash-grep-friendly, sufficient).
- Uninstall via the wizard skill (impossible bootstrap: the skill would delete itself mid-execution).

## Open questions

- **Should `install.sh` write the manifest in `--dry-run` mode too?** Tentative answer: no, dry-run does not modify the filesystem at all.
- **Should we ship a one-liner `curl ... | bash -s -- ~/proj` for uninstall?** Tentative: not in v1. Same distribution as install (clone repo, run `./scripts/uninstall.sh`).

## Migration impact

- **Existing installs (blacklist-monitor):** lack `.install-manifest.json`. Documented as a known case in the error message. Manual cleanup via git.
- **New installs:** automatically get the manifest. No user-visible change in the install flow.
