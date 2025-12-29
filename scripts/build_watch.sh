#!/usr/bin/env bash
set -euo pipefail

WITH_WATCH="yes"
if [[ "${WITH_WATCH}" != "yes" ]]; then
  echo "SKIP: WITH_WATCH != yes"
  exit 0
fi

PROJECT="${PROJECT_PATH:-}"
if [[ -z "${PROJECT}" ]]; then
  PROJECT="$(find . -maxdepth 2 -name "*.xcodeproj" -print -quit || true)"
fi
if [[ -z "${PROJECT}" ]]; then
  echo "ERROR: No .xcodeproj found. Create the Xcode project first (Step B), then re-run."
  exit 1
fi

SCHEMES_JSON="$(xcodebuild -list -json -project "$PROJECT" 2>/dev/null || true)"
DEFAULT_SCHEME="$(python3 - <<'PY'
import json,sys,re
obj=json.loads(sys.stdin.read())
schemes=obj.get("project",{}).get("schemes",[]) or []
for s in schemes:
    if re.search(r'watch', s, re.I):
        print(s); sys.exit(0)
print(schemes[0] if schemes else "")
PY
<<<"$SCHEMES_JSON")"

SCHEME="${SCHEME_WATCH:-}"
if [[ -z "${SCHEME}" ]]; then SCHEME="$DEFAULT_SCHEME"; fi
if [[ -z "${SCHEME}" ]]; then
  echo "ERROR: Cannot determine watch scheme. Set SCHEME_WATCH env var."
  exit 1
fi

echo "Building watchOS: project=$PROJECT scheme=$SCHEME"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -sdk watchsimulator \
  -destination 'generic/platform=watchOS Simulator' \
  build

echo "OK: watch build passed."
