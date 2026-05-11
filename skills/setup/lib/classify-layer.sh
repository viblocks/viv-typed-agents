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

  # Check entry_files and config_files: presence of any file at folder root.
  # If either type matches, set hit=1 and STOP checking the other indicators
  # for this skill (short-circuit; prevents over-matching via coarser globs).
  hit=0
  declared_strong=0
  for key in entry_files config_files; do
    count=$(echo "$fm" | yq eval ".detection.$key | length" - 2>/dev/null || echo 0)
    [ "$count" = "null" ] && count=0
    if [ "$count" -gt 0 ]; then
      declared_strong=1
      for i in $(seq 0 $((count-1))); do
        fname=$(echo "$fm" | yq eval ".detection.$key[$i]" -)
        if [ -f "$folder/$fname" ]; then hit=1; break; fi
      done
    fi
    [ "$hit" = "1" ] && break
  done

  # ONLY fall through to file_globs if the skill declared NO entry_files /
  # config_files (i.e. globs are the sole signal). If strong signals were
  # declared but did not match, skip this skill — globs are too coarse to
  # use as a backup (e.g. *.ts in a Vite frontend would over-match NestJS).
  if [ "$hit" = "0" ] && [ "$declared_strong" = "0" ]; then
    count=$(echo "$fm" | yq eval ".detection.file_globs | length" - 2>/dev/null || echo 0)
    [ "$count" = "null" ] && count=0
    if [ "$count" -gt 0 ]; then
     for i in $(seq 0 $((count-1))); do
      glob=$(echo "$fm" | yq eval ".detection.file_globs[$i]" -)
      ext="${glob##*.}"
      if [ -n "$ext" ] && find "$folder" -type f -name "*.$ext" -print -quit 2>/dev/null | grep -q .; then
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
