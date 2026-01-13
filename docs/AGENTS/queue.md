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

## ACTIVE — TC-WIDGET-DISPLAY-UPGRADE-V1
ID: TC-WIDGET-DISPLAY-UPGRADE-V1
Title: 小组件显示升级（更像表盘工具：circular/corner 短标签+用时；rectangular 三行；刷新频率优化）
AssignedTo: Executor

Goal:
- `accessoryCircular` / `accessoryCorner`：短标签 + 用时（信息密度高、可读）
- `accessoryRectangular`：三行（状态 / 用时 / 更新 H:mm）
- running 状态刷新更合理（30–60s），stopped 状态刷新更慢（10–15min）
- 点击 complication/widget：保持系统默认打开 App（不使用 `widgetURL`，不做深链）

AllowedFiles (ONLY):
- `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift`
- `docs/AGENTS/exec.md`（追加）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件
- 不改同步协议/业务逻辑（只改显示/刷新策略）
- 不允许添加 `.widgetURL(...)` 或 `Link(destination:)`

Time format MUST be fixed:
- If no `startedAt` or not running: `00:00`
- If elapsed < 3600s: `mm:ss` (e.g., `03:27`, `59:59`)
- If elapsed >= 3600s: `h:mm:ss` (e.g., `1:02:09`, `12:05:33`)
- 小时不补零；分钟秒两位补零

Layout requirements:
- circular/corner:
  - 状态短词：拍摄 / 选片 / 停止
  - 用时：按上述规则显示
- rectangular:
  1) 拍摄中 / 选片中 / 已停止
  2) 用时 {elapsed}
  3) 更新 H:mm（24小时制，不出现上午/下午）

Refresh policy:
- running(shooting/selecting): `TimelinePolicy.after(now + 30–60s)`（选一个具体值并写进 `docs/AGENTS/exec.md`）
- stopped: `TimelinePolicy.after(now + 10–15min)`（同上）

Acceptance:
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- 手动验证（写入 `docs/AGENTS/exec.md`）：
  - 在支持对应槽位的表盘上能添加 circular/corner/rectangular
  - 显示符合布局要求
  - 点击任意 complication/widget：能默认打开 App，不闪退

StopCondition:
- PR opened to main（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新（含用时规则/刷新策略/手动验证结果）
- STOP
