## PAUSED — TC-PREFLIGHT-EMBEDDED-WATCHAPP
ID: TC-PREFLIGHT-EMBEDDED-WATCHAPP
Status: PAUSED (postponed; return after stability restored)

## ABANDONED — TC-DEEPLINK-DL3-SCHEME
ID: TC-DEEPLINK-DL3-SCHEME
Status: ABANDONED (rollback; PR #33 closed)

## PAUSED — TC-WIDGET-TAP-OPEN-APP
ID: TC-WIDGET-TAP-OPEN-APP
Status: PAUSED (superseded by sync priority)

## DONE — TC-SYNC-PHONE-TO-WATCH-V1
ID: TC-SYNC-PHONE-TO-WATCH-V1
Status: DONE (merged)

## DONE — TC-SYNC-PHONE-TO-WATCH-V2-CONSISTENCY
ID: TC-SYNC-PHONE-TO-WATCH-V2-CONSISTENCY
Status: DONE (merged in PR #42)

## DONE — TC-SYNC-DIAG-DASHBOARD
ID: TC-SYNC-DIAG-DASHBOARD
Status: DONE (merged in PR #44)

## DONE — TC-COMPLICATION-TAP-OPEN-APP
ID: TC-COMPLICATION-TAP-OPEN-APP
Status: DONE (merged in PR #46)

## DONE — TC-CLEANUP-DEEPLINK-RESIDUALS
ID: TC-CLEANUP-DEEPLINK-RESIDUALS
Status: DONE (merged in PR #48)

## DONE — TC-WATCH-DEBUG-UI-CLEANUP
ID: TC-WATCH-DEBUG-UI-CLEANUP
Status: DONE (merged in PR #50)

## DONE — TC-WATCH-STATUS-BANNER-V1
ID: TC-WATCH-STATUS-BANNER-V1
Status: DONE (merged in PR #52)

## PAUSED — TC-WIDGET-DISPLAY-UPGRADE-V1
ID: TC-WIDGET-DISPLAY-UPGRADE-V1
Status: PAUSED (blocked by elapsed timer bug)

## DONE — TC-WIDGET-ELAPSED-TIMER-FIX
ID: TC-WIDGET-ELAPSED-TIMER-FIX
Status: DONE (merged in PR #56)

## ACTIVE — TC-WIDGET-STATE-WRITE-FIX
ID: TC-WIDGET-STATE-WRITE-FIX
Title: Widget state write fix (Swift-only)
AssignedTo: Executor

Goal:
- 切到 shooting/selecting 后，complication/widget 显示对应中文状态并且 timer 走动
- stopped 显示 已停止 `00:00`
- “更新”时间随切换更新

AllowedFiles (ONLY):
- `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`
- `docs/AGENTS/exec.md`

Forbidden:
- 不改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件

Acceptance:
- 手动：切到拍摄/选片 -> 表盘不再显示已停止，且用时会走；切回停止 -> 已停止 `00:00`
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- `docs/AGENTS/exec.md` 写明根因与修复点

StopCondition:
- PR opened to main（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新
- STOP
