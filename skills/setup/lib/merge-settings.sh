#!/usr/bin/env bash
# merge-settings.sh <consumer-settings.json> <fragment.json>
# Deep-merges fragment into consumer settings. Creates consumer file if missing.
#
# Metadata keys: any key starting with `_` (e.g. `_comment`) is treated as
# fragment-internal metadata and is NEVER merged into the consumer. This
# convention keeps the consumer's settings.json clean and avoids leaking
# fragment documentation strings on uninstall (the reverse operation cannot
# distinguish a leaked metadata scalar from a user-provided one).

set -euo pipefail

target="${1:?settings.json path required}"
fragment="${2:?fragment.json path required}"

[ -f "$fragment" ] || { echo "fragment not found: $fragment" >&2; exit 2; }

# Pre-clean the fragment: recursively drop any object key starting with `_`.
fragment_clean=$(mktemp)
jq 'walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)' \
  "$fragment" > "$fragment_clean"

if [ ! -f "$target" ]; then
  cp "$fragment_clean" "$target"
  rm -f "$fragment_clean"
  exit 0
fi

tmp=$(mktemp)
# jq deep merge: scalar values from right side win, arrays concatenate with dedupe,
# objects merge recursively.
jq -n --slurpfile t "$target" --slurpfile f "$fragment_clean" '
  def merge_array_aware($a; $b):
    if ($a | type) == "object" and ($b | type) == "object" then
      reduce ($b | keys_unsorted[]) as $k ($a;
        if (.[$k] | type) == "array" and ($b[$k] | type) == "array"
        then .[$k] = (.[$k] + $b[$k] | unique_by(tostring))
        elif (.[$k] | type) == "object" and ($b[$k] | type) == "object"
        then .[$k] = merge_array_aware(.[$k]; $b[$k])
        else .[$k] = $b[$k]
        end)
    else $b
    end;
  merge_array_aware($t[0]; $f[0])
' > "$tmp"
mv "$tmp" "$target"
rm -f "$fragment_clean"
