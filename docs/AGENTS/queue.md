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

## DONE — TC-SPEC-V1-ALIGNMENT
ID: TC-SPEC-V1-ALIGNMENT
Status: DONE (merged in PR #61)

## PAUSED — TC-WIDGET-STATE-WRITE-FIX
ID: TC-WIDGET-STATE-WRITE-FIX
Status: PAUSED (spec alignment priority)

## ACTIVE — TC-IOS-HOME-TIMELINE-V1
ID: TC-IOS-HOME-TIMELINE-V1
Title: iOS 首页会话时间线（按时间早→晚；显示从下到上）
AssignedTo: Executor

Goal:
- 在 iOS 首页加入一个“会话时间线”区块，展示 stage 变化记录（拍摄/选片/停止）与时间戳。
- 排序规则：按时间从早到晚（ascending），但视觉呈现从下到上（最新在上方）。
- 不修改 watch/widget/config，避免牵连手表端。

Scope (Allowed files ONLY):
- 仅 iOS 目录：PhotoFlow/PhotoFlow/**（iPhone app Swift files）
- docs/AGENTS/exec.md（追加）

Forbidden:
- 禁止修改：
  - PhotoFlow/PhotoFlowWatch Watch App/**
  - PhotoFlow/PhotoFlowWatchWidget/**
  - *.plist / *.entitlements / project.pbxproj
- 不新增 target/build settings
- 不重构现有架构（只加一个轻量 timeline）

Acceptance:
- 首页出现 timeline 区块（标题：例如“今日时间线/会话时间线”）
- 记录项包含：时间（HH:mm:ss 或 HH:mm）、stage 中文（拍摄/选片/停止）、来源（手机/手表可选，若暂无则先留空）
- 排序：数据按时间升序；UI 显示最新在上（通过 reversed/rotation 等实现均可）
- 运行护栏：bash scripts/ios_safe.sh --clean-deriveddata PASS
- xcodebuild（ios_safe 自带）通过
- exec.md 记录：实现方式、排序逻辑、手动验证 PASS

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新
- STOP
