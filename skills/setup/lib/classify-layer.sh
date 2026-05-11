#!/usr/bin/env bash
# classify-layer.sh <project-path> <service-folder-rel> <skills-dir>
# Reads detection signatures from skills-dir/**/SKILL.md frontmatter,
# applies them to the service folder, prints: backend | frontend | ambiguous.

set -euo pipefail

project="${1:-}"
service="${2:-}"
skills_dir="${3:-.claude/skills}"

[ -d "$project/$service" ] || { echo "ambiguous"; exit 0; }
[ -d "$skills_dir" ] || { echo "ambiguous"; exit 0; }

folder="$project/$service"
matched_backend=0
matched_frontend=0

# Iterate all SKILL.md files with a `detection:` block.
while IFS= read -r skill_file; do
  # Extract frontmatter (between first two --- markers).
  fm=$(awk '/^---$/{c++;next} c==1{print} c>=2{exit}' "$skill_file")
  # Skip if no detection block.
  echo "$fm" | grep -q "^detection:" || continue

  # Parse layer.
  layer=$(echo "$fm" | yq eval '.detection.layer' -)
  [ "$layer" = "null" ] && continue

  # Check entry_files and config_files first: presence of any named file at
  # folder root. If either matches, this skill is confirmed and we can skip
  # the file_globs fallback.
  hit=0
  for key in entry_files config_files; do
    count=$(echo "$fm" | yq eval ".detection.$key | length" - 2>/dev/null || echo 0)
    [ "$count" = "null" ] && count=0
    if [ "$count" -gt 0 ]; then
      for i in $(seq 0 $((count-1))); do
        fname=$(echo "$fm" | yq eval ".detection.$key[$i]" -)
        if [ -f "$folder/$fname" ]; then hit=1; break; fi
      done
    fi
    [ "$hit" = "1" ] && break
  done

  # Fallback to file_globs whenever entry_files/config_files did not match,
  # regardless of whether they were declared. We use a portable find-based
  # glob match (see below) so patterns like src/**/*.module.ts mean what they
  # say (proper recursion within a subdirectory), not just "any .ts file"
  # which would over-match.
  if [ "$hit" = "0" ]; then
    count=$(echo "$fm" | yq eval ".detection.file_globs | length" - 2>/dev/null || echo 0)
    [ "$count" = "null" ] && count=0
    if [ "$count" -gt 0 ]; then
     for i in $(seq 0 $((count-1))); do
      glob=$(echo "$fm" | yq eval ".detection.file_globs[$i]" -)
      # Portable glob match (works on macOS bash 3.2, no globstar required).
      # Convert glob to a find(1) -path pattern. find's `*` already matches
      # across `/`, so a recursive `**/` collapses to nothing — `src/**/*.x`
      # becomes `src/*.x`, which `-path` then matches at any depth.
      pattern=$(printf '%s' "$glob" | sed -e 's|/\*\*/|/|g' -e 's|^\*\*/||' -e 's|/\*\*$||' -e 's|\*\*|*|g')
      if find "$folder" -type f -path "$folder/$pattern" -print -quit 2>/dev/null | grep -q .; then
        hit=1; break
      fi
     done
    fi
  fi

  if [ "$hit" = "1" ]; then
    case "$layer" in
      backend)  matched_backend=1 ;;
      frontend) matched_frontend=1 ;;
    esac
  fi
done < <(find "$skills_dir" -name SKILL.md)

if [ "$matched_backend" = "1" ] && [ "$matched_frontend" = "1" ]; then
  echo "ambiguous"
elif [ "$matched_backend" = "1" ]; then
  echo "backend"
elif [ "$matched_frontend" = "1" ]; then
  echo "frontend"
else
  echo "ambiguous"
fi
