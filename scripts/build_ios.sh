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

SCHEMES_JSON="$(xcodebuild -list -json -project "$PROJECT" 2>/dev/null || true)"
if [[ -z "${SCHEMES_JSON}" ]]; then
  echo "ERROR: xcodebuild -list failed for project: $PROJECT"
  exit 1
fi

DEFAULT_SCHEME="$(SCHEMES_JSON="$SCHEMES_JSON" python3 - <<'PY'
import json,os
raw = os.environ.get("SCHEMES_JSON", "").strip()
obj = json.loads(raw) if raw else {}
schemes = obj.get("project", {}).get("schemes", []) or []
print(schemes[0] if schemes else "")
PY
)"

SCHEME="${SCHEME_IOS:-PhotoFlow}"
if [[ -z "${SCHEME}" ]]; then SCHEME="$DEFAULT_SCHEME"; fi
if [[ -z "${SCHEME}" ]]; then
  echo "ERROR: Cannot determine iOS scheme. Set SCHEME_IOS env var."
  exit 1
fi

echo "Building iOS: project=$PROJECT scheme=$SCHEME"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "OK: iOS build passed."
