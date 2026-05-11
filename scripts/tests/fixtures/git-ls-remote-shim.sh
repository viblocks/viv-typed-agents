#!/usr/bin/env bash
# Fake git for tests. Intercepts `git ls-remote <url> <ref>` and returns
# a fixture SHA based on (url, ref). All other git invocations delegate
# to the real git binary.
#
# Activate by prepending its directory to PATH and renaming/symlinking
# this file to `git` in that dir.

if [ "$1" = "ls-remote" ] && [ "$#" -ge 3 ]; then
  url="$2"
  ref="$3"
  case "$url:$ref" in
    "https://fake.test/comp-current:main")     echo "aaaaaaa1111111111111111111111111111111  refs/heads/main";;
    "https://fake.test/comp-behind:main")      echo "ddddddd2222222222222222222222222222222  refs/heads/main";;
    "https://fake.test/comp-also-behind:main") echo "eeeeeee3333333333333333333333333333333  refs/heads/main";;
    "https://fake.test/comp-behind:v1.0.0")    echo "fffffff4444444444444444444444444444444  refs/tags/v1.0.0";;
    *) exit 2;;
  esac
  exit 0
fi

# Delegate everything else to the real git, found by skipping our own PATH entry.
SHIM_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${SHIM_DIR}\$" | tr '\n' ':' | sed 's/:$//')
exec git "$@"
