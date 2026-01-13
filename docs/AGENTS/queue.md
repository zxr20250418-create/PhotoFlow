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

## ACTIVE — TC-WIDGET-ELAPSED-TIMER-FIX
ID: TC-WIDGET-ELAPSED-TIMER-FIX
Title: 表盘/小组件用时从 00:00 改为运行中自动走动（Swift-only）
AssignedTo: Executor

Goal:
- running（拍摄/选片）时，complication/widget 的用时能自动走动（每秒更新）
- stopped 时仍显示 00:00
- 不引入任何安装/打包风险

AllowedFiles (ONLY):
- `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift`
- `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`（仅在写入 startedAt/isRunning 的位置改）
- `docs/AGENTS/exec.md`（追加）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件
- 不改同步协议/业务逻辑（只补 startedAt 与显示逻辑）

Acceptance:
1) Widget 显示逻辑：
   - 如果 running 且 startedAt 存在：用 `Text(startedAtDate, style: .timer)` 显示用时（自动每秒更新）
   - 其它情况：显示 `00:00`
2) Watch 写入逻辑：
   - 进入 shooting/selecting 时：确保 `isRunning=true`；`startedAt` 为空则写 `Date()`
   - stopped 时：`isRunning=false`（`startedAt` 是否清空按当前逻辑即可）
   - 保持 `reloadTimelines` 调用不变
3) `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
   - `PhotoFlowWatch Watch App`（watchOS simulator）
   - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
   - `PhotoFlow`（iphoneos）
4) 手动验证（写进 `docs/AGENTS/exec.md`）：
   - 切到拍摄/选片后，表盘用时开始走
   - 切到停止后，用时回到 `00:00`

StopCondition:
- PR opened to main（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新
- STOP
