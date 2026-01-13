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

## ACTIVE — TC-WATCH-STATUS-BANNER-V1
ID: TC-WATCH-STATUS-BANNER-V1
Title: Watch 主界面连接状态 + 最近同步时间（非 Debug）+ 轻微触感反馈
AssignedTo: Executor

Goal:
- watch 主界面默认显示一条小状态信息：
  - 连接：已连接/未连接（基于 WCSession activationState/isReachable）
  - 最近同步：HH:mm:ss（基于 lastReceived/lastApplied 时间戳）
- 在 watch 端切换 stage（拍摄/选片/停止）时给轻微 haptic 反馈
- 不影响现有同步逻辑与小组件显示

AllowedFiles (ONLY):
- `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`
- （如确实需要）watch 侧 WCSession 管理文件（仅用于读连接状态/时间戳，不改协议）
- `docs/AGENTS/exec.md`

Forbidden:
- 不改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件
- 不改同步协议字段（只读现有数据）

Acceptance:
- watch 主界面默认可见状态条（非 Debug）
- 断连时显示“未连接”，连上后变“已连接”
- 最近同步时间会随接收/应用更新而刷新
- stage 切换触发轻微 haptic
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- `docs/AGENTS/exec.md` 记录字段来源与验证步骤/结果

StopCondition:
- PR opened to main（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新
- STOP
