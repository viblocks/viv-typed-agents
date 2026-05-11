#!/usr/bin/env bash
# unmerge-settings.sh <consumer-settings.json> <fragment.json>
# Inverse of merge-settings.sh: remove entries from consumer that match
# fragment. Preserves all other user keys. Idempotent. If the consumer
# becomes top-level {} after unmerge, delete the file.

set -euo pipefail
target="${1:?settings.json path required}"
fragment="${2:?fragment.json path required}"

[ -f "$target" ]   || { echo "target not found: $target" >&2; exit 0; }
[ -f "$fragment" ] || { echo "fragment not found: $fragment" >&2; exit 2; }

tmp=$(mktemp)
jq -n --slurpfile t "$target" --slurpfile f "$fragment" '
  def unmerge_array_aware($a; $b):
    reduce ($b | keys[]) as $k ($a;
      if ($a[$k] | type) == "array" and ($b[$k] | type) == "array"
      then .[$k] = ($a[$k] | map(. as $x | select(($b[$k] | index($x)) == null)))
           | if .[$k] == [] then del(.[$k]) else . end
      elif ($a[$k] | type) == "object" and ($b[$k] | type) == "object"
      then .[$k] = unmerge_array_aware($a[$k]; $b[$k])
           | if .[$k] == {} then del(.[$k]) else . end
      else .
      end);
  unmerge_array_aware($t[0]; $f[0])
' > "$tmp"
mv "$tmp" "$target"

if [ "$(jq -c '.' "$target")" = "{}" ]; then
  rm -f "$target"
fi
