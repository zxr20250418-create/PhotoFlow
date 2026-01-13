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

## ACTIVE — TC-CLEANUP-DEEPLINK-RESIDUALS
ID: TC-CLEANUP-DEEPLINK-RESIDUALS
Title: 清理深链残留（photoflow/onOpenURL/DEBUG deep link），避免未来误触
AssignedTo: Executor

Goal:
- 移除所有深链相关残留：`photoflow://`、`onOpenURL`/`handleDeepLink`、`DEBUG` stage 深链测试入口
- 保持当前目标：点表盘 complication 仍能默认打开 App（PR #46 已合并）
- 不触碰任何打包/安装高风险配置

Scope (Allowed files ONLY):
- `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`（或 watch app root 入口文件）
- `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift`（仅做引用清理，若有残留）
- `docs/AGENTS/exec.md`（追加记录）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件
- 不重构业务状态机/同步逻辑（只做深链相关代码移除）

Acceptance:
- 仓库中不再出现关键字：
  - `photoflow://`、`handleDeepLink`、`onOpenURL`、`DEBUG: stage`
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- 手动验证（写入 `docs/AGENTS/exec.md`）：
  - watch app 从列表打开不闪退
  - 点表盘 complication 仍能打开 App（默认入口）

StopCondition:
- PR opened to main（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新（列出删掉了哪些 deep link 入口与关键字检查命令）
- STOP
