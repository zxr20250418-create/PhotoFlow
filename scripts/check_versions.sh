#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT_PATH:-}"
if [[ -z "${PROJECT}" ]]; then
  PROJECT="$(find . -maxdepth 2 -name "*.xcodeproj" -print -quit || true)"
fi
if [[ -z "${PROJECT}" ]]; then
  echo "ERROR: No .xcodeproj found. Create the Xcode project first (Step B), then re-run."
  exit 1
fi

SCHEMES_JSON="$(xcodebuild -list -json -project "$PROJECT" 2>/dev/null)"
SCHEMES="$(SCHEMES_JSON="$SCHEMES_JSON" python3 - <<'PY'
import json,os
raw = os.environ.get("SCHEMES_JSON", "").strip()
obj = json.loads(raw) if raw else {}
schemes = obj.get("project", {}).get("schemes", []) or []
print("\n".join(schemes))
PY
)"

if [[ -z "${SCHEMES}" ]]; then
  echo "ERROR: No schemes found in project: $PROJECT"
  exit 1
fi

echo "Checking versions across schemes in: $PROJECT"
printf "%-40s %-15s %-10s\n" "SCHEME" "MARKETING_VERSION" "BUILD"

declare -a versions=()
declare -a builds=()

while IFS= read -r scheme; do
  [[ -z "$scheme" ]] && continue
  settings="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$scheme" 2>/dev/null || true)"
  if [[ -z "$settings" ]]; then
    echo "WARN: cannot read build settings for scheme: $scheme (skipped)"
    continue
  fi
  mv="$(printf "%s\n" "$settings" | awk -F' = ' '$1 ~ /MARKETING_VERSION$/ { if (!seen) { print $2; seen=1 } }')"
  bv="$(printf "%s\n" "$settings" | awk -F' = ' '$1 ~ /CURRENT_PROJECT_VERSION$/ { if (!seen) { print $2; seen=1 } }')"

  printf "%-40s %-15s %-10s\n" "$scheme" "${mv:-<empty>}" "${bv:-<empty>}"

  [[ -n "${mv:-}" ]] && versions+=("$mv")
  [[ -n "${bv:-}" ]] && builds+=("$bv")
 done <<<"$SCHEMES"

if [[ ${#versions[@]} -eq 0 || ${#builds[@]} -eq 0 ]]; then
  echo "ERROR: Failed to extract MARKETING_VERSION or BUILD from schemes."
  exit 1
fi

uniq_versions="$(printf "%s\n" "${versions[@]}" | sort -u | wc -l | tr -d ' ')"
uniq_builds="$(printf "%s\n" "${builds[@]}" | sort -u | wc -l | tr -d ' ')"

if [[ "$uniq_versions" != "1" || "$uniq_builds" != "1" ]]; then
  echo "ERROR: Version/Build mismatch detected."
  exit 1
fi

echo "OK: All schemes share MARKETING_VERSION=${versions[0]} and BUILD=${builds[0]}"
