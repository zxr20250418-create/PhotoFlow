#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

app_ex="${APP_EX:-}"
if [[ -z "$app_ex" ]]; then
  app_ex=$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/PhotoFlow-"*/Build/Products/Debug-iphoneos/PhotoFlow.app/Watch/*Watch*.app/PlugIns/PhotoFlowWatchWidgetExtension.appex 2>/dev/null | head -n 1 || true)
fi

if [[ -z "$app_ex" ]]; then
  fail "embedded widget appex not found (set APP_EX to override)"
fi

if [[ "$app_ex" == "~/"* ]]; then
  app_ex="$HOME/${app_ex#~/}"
fi

if [[ ! -d "$app_ex" ]]; then
  fail "appex path not found: $app_ex"
fi

plist="$app_ex/Info.plist"
if [[ ! -f "$plist" ]]; then
  fail "Info.plist missing in appex: $plist"
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true
}

cf_exe="$(plist_value CFBundleExecutable)"
if [[ -z "$cf_exe" ]]; then
  fail "CFBundleExecutable missing or empty"
fi

if [[ ! -f "$app_ex/$cf_exe" ]]; then
  fail "CFBundleExecutable file missing: $app_ex/$cf_exe"
fi

cf_name="$(plist_value CFBundleName)"
if [[ -z "$cf_name" ]]; then
  fail "CFBundleName missing or empty"
fi

ext_point="$(plist_value NSExtension:NSExtensionPointIdentifier)"
if [[ "$ext_point" != "com.apple.widgetkit-extension" ]]; then
  fail "NSExtensionPointIdentifier invalid: $ext_point"
fi

if /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPrincipalClass" "$plist" >/dev/null 2>&1; then
  fail "NSExtensionPrincipalClass must be absent"
fi

if /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionMainStoryboard" "$plist" >/dev/null 2>&1; then
  fail "NSExtensionMainStoryboard must be absent"
fi

echo "ALL CHECKS PASSED"
