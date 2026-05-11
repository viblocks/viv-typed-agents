#!/usr/bin/env bash
# write-routing.sh <output-path> <plan-json-file>
# Writes or merges routing-table.json. Plan is a JSON array of route objects.
# Merge rule: by `domain` key. Existing entries keep paths/implementer/reviewer
# if they differ from plan (user may have hand-edited); new entries are added.

set -euo pipefail

out="${1:?output-path required}"
plan="${2:?plan-json-file required}"

[ -f "$plan" ] || { echo "plan not found: $plan" >&2; exit 2; }

mkdir -p "$(dirname "$out")"

if [ ! -f "$out" ]; then
  # Fresh write.
  jq --slurpfile p "$plan" '{
    "$schema": "./schema/routing-table.schema.json",
    "version": "1.0",
    "routes": $p[0]
  }' <<<'{}' > "$out"
  exit 0
fi

# Merge: keep existing entries unchanged; append new ones whose domain is absent.
tmp=$(mktemp)
jq --slurpfile p "$plan" '
  .routes as $existing
  | ($p[0] | map(select(.domain as $d | ($existing | map(.domain) | index($d)) == null))) as $new
  | .routes = $existing + $new
' "$out" > "$tmp" && mv "$tmp" "$out"
