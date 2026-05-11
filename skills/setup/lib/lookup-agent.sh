#!/usr/bin/env bash
# lookup-agent.sh <agents-dir> <domain> <business_domain> <type>
# Prints the matching agent's `name` from frontmatter. Exits 1 if no match.

set -euo pipefail

agents_dir="${1:?agents-dir required}"
want_domain="${2:?domain required}"
want_bd="${3:?business_domain required}"
want_type="${4:?type required}"

[ -d "$agents_dir" ] || { exit 1; }

match=""
while IFS= read -r f; do
  fm=$(awk '/^---$/{c++;next} c==1{print} c>=2{exit}' "$f")
  d=$(echo "$fm" | yq eval '.domain // ""' -)
  bd=$(echo "$fm" | yq eval '.business_domain // ""' -)
  t=$(echo "$fm" | yq eval '.type // ""' -)
  if [ "$d" = "$want_domain" ] && [ "$bd" = "$want_bd" ] && [ "$t" = "$want_type" ]; then
    name=$(echo "$fm" | yq eval '.name' -)
    if [ -n "$match" ]; then
      echo "multiple matches for $want_domain/$want_bd/$want_type" >&2
      exit 1
    fi
    match="$name"
  fi
done < <(find "$agents_dir" -name "*.md")

[ -n "$match" ] || exit 1
echo "$match"
