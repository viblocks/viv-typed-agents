# scripts/tests

Bash tests for scripts in `scripts/`. Run from repo root:

    bash scripts/tests/upgrade.test.sh

Tests use a `git` shim (`fixtures/git-ls-remote-shim.sh`) prepended to `PATH`
so `git ls-remote` returns fixture SHAs without hitting the network. All other
git operations delegate to the real binary.

Each test runs `upgrade.sh` in a fresh tempdir against a copy of
`fixtures/MANIFEST.test.yaml`.
