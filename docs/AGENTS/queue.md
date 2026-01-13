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

## ACTIVE — TC-SYNC-DIAG-DASHBOARD
ID: TC-SYNC-DIAG-DASHBOARD
Title: 同步诊断面板（Debug-only，可视化最近 payload 与状态）
AssignedTo: Executor

Goal:
- 在 iPhone 端与 Watch 端各提供一个 Debug-only “Sync Diagnostics” 面板，显示：
  - lastSent payload（stage/isRunning/startedAt/lastUpdatedAt/seq）
  - lastReceived payload（同字段）
  - lastAppliedSeq/ts（watch 端）
  - WCSession activationState / isReachable / isPaired / isWatchAppInstalled（各端合适字段）
- 默认不影响正常 UI：仅在 DEBUG 下通过隐藏入口进入。

Scope (Allowed files ONLY):
- iPhone: `PhotoFlow/PhotoFlow/ContentView.swift`
- Watch: `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`
- `docs/AGENTS/exec.md`（追加）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件（必须内嵌实现）
- 不改同步协议，只做可视化读取（复用现有状态）

Acceptance:
- Debug 模式下能打开诊断面板，字段可读且会随发送/接收更新
- Release/正常使用路径不出现 Debug UI
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`
  - `PhotoFlowWatchWidgetExtension`
  - `PhotoFlow`（iphoneos）
- `docs/AGENTS/exec.md` 记录入口方式与字段说明

StopCondition:
- PR opened to `main`（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新
- STOP
