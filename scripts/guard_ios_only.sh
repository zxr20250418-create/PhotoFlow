#!/usr/bin/env bash
set -euo pipefail

base_ref="origin/main"
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  base_ref="main"
fi

allow_watch_swift="${ALLOW_WATCH_SWIFT:-0}"

changed_files="$( { \
  git diff --name-only "$base_ref"...HEAD; \
  git diff --name-only --cached; \
  git diff --name-only; \
  git ls-files --others --exclude-standard; \
} | sed '/^$/d' | sort -u )"

declare -a forbidden=()
while IFS= read -r file; do
  [ -z "$file" ] && continue
  case "$file" in
    "PhotoFlow/PhotoFlowWatch Watch App/"*)
      if [ "$allow_watch_swift" = "1" ] && [[ "$file" == *.swift ]]; then
        continue
      fi
      forbidden+=("$file")
      ;;
    "PhotoFlow/PhotoFlowWatchWidget/"*)
      if [ "$allow_watch_swift" = "1" ] && [[ "$file" == *.swift ]]; then
        continue
      fi
      forbidden+=("$file")
      ;;
    # keep config and project files blocked
    *.entitlements|\
    *.plist|\
    *.xcodeproj/project.pbxproj)
      forbidden+=("$file")
      ;;
  esac
done <<< "$changed_files"

if [ ${#forbidden[@]} -gt 0 ]; then
  echo "Forbidden changes detected (against $base_ref):"
  for file in "${forbidden[@]}"; do
    echo " - $file"
  done
  exit 1
fi

echo "No forbidden changes detected (against $base_ref)."
