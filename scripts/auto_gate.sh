#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LOCAL_BUILD="${LOCAL_BUILD:-true}"
VERIFY_OUT="${VERIFY_OUT:-docs/AGENTS/verify.md}"

mkdir -p artifacts docs/AGENTS

branch="$(git branch --show-current)"
head_sha="$(git rev-parse --short HEAD)"
ts="$(date -Iseconds)"

pass=true
ios_log="artifacts/ios_build_${head_sha}.log"
watch_log="artifacts/watch_build_${head_sha}.log"

echo "==> Auto Gate (LOCAL_BUILD=$LOCAL_BUILD) branch=$branch head=$head_sha"

if [[ "$LOCAL_BUILD" == "true" ]]; then
  echo "==> Build iOS..."
  if ! xcodebuild -project "$XCODEPROJ" \
      -scheme "$IOS_SCHEME" \
      -destination 'generic/platform=iOS Simulator' \
      build 2>&1 | tee "$ios_log" >/dev/null; then
    pass=false
  fi

  if [[ -n "${WATCH_SCHEME:-}" ]]; then
    echo "==> Build watch..."
    if ! xcodebuild -project "$XCODEPROJ" \
        -scheme "$WATCH_SCHEME" \
        -destination 'generic/platform=watchOS Simulator' \
        build 2>&1 | tee "$watch_log" >/dev/null; then
      pass=false
    fi
  fi
else
  echo "==> Skip local build."
fi

{
  echo "# Automated Gate"
  echo
  echo "- Time: $ts"
  echo "- Branch: $branch"
  echo "- Head: $head_sha"
  echo "- LOCAL_BUILD: $LOCAL_BUILD"
  echo "- XCODEPROJ: $XCODEPROJ"
  echo "- IOS_SCHEME: $IOS_SCHEME"
  echo "- WATCH_SCHEME: ${WATCH_SCHEME:-<empty>}"
  echo
  echo "## Build logs"
  if [[ "$LOCAL_BUILD" == "true" ]]; then
    echo "- iOS: $ios_log"
    if [[ -n "${WATCH_SCHEME:-}" ]]; then
      echo "- watch: $watch_log"
    fi
  else
    echo "- (skipped)"
  fi
  echo
  if [[ "$pass" == "true" ]]; then
    echo "AUTO_GATE=PASS"
  else
    echo "AUTO_GATE=FAIL"
  fi
  echo
  echo "## Git snapshot"
  git status -sb || true
  echo
  echo "## Recent commits"
  git log --oneline -n 10 || true
} > "$VERIFY_OUT"

echo "==> Wrote $VERIFY_OUT"
grep -E "AUTO_GATE=" "$VERIFY_OUT" || true

if [[ "$pass" != "true" ]]; then
  echo "==> Auto gate FAILED. Fix build issues, then rerun."
  exit 1
fi
