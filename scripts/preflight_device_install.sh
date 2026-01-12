#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*

xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO

"${ROOT_DIR}/scripts/check_embedded_watch_app.sh"

if [[ -x "${ROOT_DIR}/scripts/check_embedded_widget_appex.sh" ]]; then
  "${ROOT_DIR}/scripts/check_embedded_widget_appex.sh"
else
  echo "WARN: scripts/check_embedded_widget_appex.sh not found; skipping."
fi

echo "ALL PREFLIGHTS PASSED"
