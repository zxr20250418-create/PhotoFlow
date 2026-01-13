#!/bin/bash
set -euo pipefail

fail=0

pass_msg() {
  echo "PASS: $1"
}

warn_msg() {
  echo "WARN: $1"
}

fail_msg() {
  echo "FAIL: $1" >&2
  fail=1
}

IOS_APP="${IOS_APP:-$(ls -d ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*/Build/Products/Debug-iphoneos/PhotoFlow.app 2>/dev/null | head -n 1)}"
if [[ -z "${IOS_APP}" || ! -d "${IOS_APP}" ]]; then
  fail_msg "IOS_APP not found. Set IOS_APP or build Debug-iphoneos PhotoFlow.app first."
  exit 1
fi

WATCH_APP="${WATCH_APP:-${IOS_APP}/Watch/PhotoFlowWatch Watch App.app}"
if [[ ! -d "${WATCH_APP}" ]]; then
  fail_msg "WATCH_APP not found at ${WATCH_APP}"
  exit 1
fi

WATCH_PLIST="${WATCH_APP}/Info.plist"
if [[ ! -f "${WATCH_PLIST}" ]]; then
  fail_msg "Info.plist missing at ${WATCH_PLIST}"
  exit 1
fi

PLIST_DUMP=$(plutil -p "${WATCH_PLIST}")

if echo "${PLIST_DUMP}" | grep -q '"WKWatchKitApp" => 1'; then
  pass_msg "WKWatchKitApp present and true"
else
  fail_msg "WKWatchKitApp missing or not true"
fi

if echo "${PLIST_DUMP}" | grep -q '"WKApplication"'; then
  fail_msg "WKApplication present (must be absent)"
else
  pass_msg "WKApplication absent"
fi

if echo "${PLIST_DUMP}" | grep -Eq '"WKCompanionAppBundleIdentifier" => "[^"]+"'; then
  pass_msg "WKCompanionAppBundleIdentifier present"
else
  fail_msg "WKCompanionAppBundleIdentifier missing or empty"
fi

if echo "${PLIST_DUMP}" | awk 'BEGIN{in=0;found=0} /"UIDeviceFamily"/ {in=1} in && /=> 4/ {found=1} in && /^\s*]/ {exit found?0:1} END{exit found?0:1}'; then
  pass_msg "UIDeviceFamily includes 4"
else
  fail_msg "UIDeviceFamily missing 4"
fi

if echo "${PLIST_DUMP}" | grep -q 'photoflow'; then
  pass_msg "CFBundleURLTypes includes photoflow"
else
  if [[ "${REQUIRE_PHOTOFLOW_URL:-0}" == "1" ]]; then
    fail_msg "CFBundleURLTypes missing photoflow (REQUIRE_PHOTOFLOW_URL=1)"
  else
    warn_msg "CFBundleURLTypes missing photoflow"
  fi
fi

if [[ ! -d "${WATCH_APP}/PlugIns" ]]; then
  fail_msg "PlugIns directory missing in Watch app"
else
  shopt -s nullglob
  watchkit_found=0
  for appex in "${WATCH_APP}/PlugIns"/*.appex; do
    if [[ -f "${appex}/Info.plist" ]]; then
      if plutil -p "${appex}/Info.plist" | grep -q '"NSExtensionPointIdentifier" => "com.apple.watchkit"'; then
        watchkit_found=1
        pass_msg "Found WatchKit extension appex: $(basename "${appex}")"
        break
      fi
    fi
  done
  shopt -u nullglob

  if [[ ${watchkit_found} -ne 1 ]]; then
    fail_msg "No WatchKit extension appex with NSExtensionPointIdentifier=com.apple.watchkit found"
  fi
fi

if [[ ${fail} -ne 0 ]]; then
  echo "FAIL: one or more checks failed" >&2
  exit 1
fi

echo "ALL CHECKS PASSED"
