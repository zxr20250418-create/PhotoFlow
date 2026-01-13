## PAUSED — TC-PREFLIGHT-EMBEDDED-WATCHAPP
ID: TC-PREFLIGHT-EMBEDDED-WATCHAPP
Status: PAUSED (postponed; return after stability restored)

## ABANDONED — TC-DEEPLINK-DL3-SCHEME
ID: TC-DEEPLINK-DL3-SCHEME
Status: ABANDONED (rollback; PR #33 closed)

## ACTIVE — TC-WIDGET-TAP-OPEN-APP
ID: TC-WIDGET-TAP-OPEN-APP
Title: Widget tap opens watch app (no deep link)
AssignedTo: Executor

Goal:
- Remove `photoflow://...` deep link usage from the watch widget/complication so tapping opens the watch app without requiring URL scheme registration.
- Ensure watch app launches from app list without crashing.

AllowedFiles (ONLY):
- `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift`
- (optional, cleanup only) `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift` (remove deep-link DEBUG UI only; do not change business logic)
- `docs/AGENTS/exec.md`

Forbidden:
- Do NOT modify `Info.plist`, `project.pbxproj`, entitlements, targets, or build settings.

Acceptance:
- Widget/complication no longer sets `widgetURL` to `photoflow://...` (remove the deep link).
- Watch app launches from the app list without crashing; tapping widget/complication does not crash.
- Builds succeed (`CODE_SIGNING_ALLOWED=NO` ok):
  - `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`

StopCondition:
- PR opened to `main` (DO NOT MERGE), CI green, `docs/AGENTS/exec.md` updated with summary + verification commands; STOP.
