#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "==> xcodebuild -list"
xcodebuild -list -project "$XCODEPROJ" | sed -n '1,200p' || true
echo

echo "==> Build iOS: $IOS_SCHEME"
xcodebuild -project "$XCODEPROJ" \
  -scheme "$IOS_SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  build
echo "OK: iOS build passed."
echo

if [[ -n "${WATCH_SCHEME:-}" ]]; then
  echo "==> Build watch: $WATCH_SCHEME"
  xcodebuild -project "$XCODEPROJ" \
    -scheme "$WATCH_SCHEME" \
    -destination 'generic/platform=watchOS Simulator' \
    build
  echo "OK: watch build passed."
fi
