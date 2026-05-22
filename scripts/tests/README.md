# scripts/tests

Bash tests for scripts and behavioral fixtures in this repo. Run from repo root:

    bash scripts/tests/upgrade.test.sh
    bash scripts/tests/per-item-atomicity.test.sh

## `upgrade.test.sh`

Tests `scripts/upgrade.sh`. Uses a `git` shim (`fixtures/git-ls-remote-shim.sh`)
prepended to `PATH` so `git ls-remote` returns fixture SHAs without hitting the
network. All other git operations delegate to the real binary.

Each test runs `upgrade.sh` in a fresh tempdir against a copy of
`fixtures/MANIFEST.test.yaml`.

## `per-item-atomicity.test.sh`

Regression test for the Per-Item Atomicity Contract (SPEC §3.3, ADR-RD-013).
Exercises `fixtures/atomic-worker.sh` — a reference bash impl of the contract —
under simulated abrupt termination and the three declared failure policies
(`abort`, `skip`, `retry`).

The fixture is a **behavioral** simulation: real typed agents are LLM prompts,
not bash. The fixture exists so we can mechanically verify the contract's
invariants without depending on LLM execution. The invariant verified:

> At any termination point, items 1..K-1 are independently valid; item K is
> either fully committed or fully rolled back (never partial).

Scenarios covered: happy path (N=5), SIGKILL after tmp-write at item K, SIGKILL
after validate at item K, validation failure × {abort, skip, retry+succeed,
retry+fail-to-abort}.
