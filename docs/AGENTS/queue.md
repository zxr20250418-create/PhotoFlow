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

## ABANDONED — TC-IOS-HOME-TIMELINE-V1
ID: TC-IOS-HOME-TIMELINE-V1
Status: ABANDONED (PR #64 closed; raw event log direction rejected)

## DONE — TC-IOS-HOME-TIMELINE-SPEC-LOCK
ID: TC-IOS-HOME-TIMELINE-SPEC-LOCK
Status: DONE (merged in PR #66)

## DONE — TC-IOS-BOTTOMBAR-NEXTACTION-V1
ID: TC-IOS-BOTTOMBAR-NEXTACTION-V1
Status: DONE (merged in PR #69)

## PAUSED — TC-IOS-HOME-TIMELINE-V2
ID: TC-IOS-HOME-TIMELINE-V2
Title: iOS 首页会话时间线（会话聚合，非 raw log）
AssignedTo: Executor
Status: PAUSED (awaiting PR #68 merge)

Goal:
- 基于 SPEC-LOCK（docs/SPEC.md）实现 iPhone 首页“会话时间线”。
- 按会话聚合展示，杜绝 raw log 追加刷屏，不大改首页结构。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（追加）

Forbidden:
- 禁止修改：
  - PhotoFlow/PhotoFlowWatch Watch App/**
  - PhotoFlow/PhotoFlowWatchWidget/**
  - **/Info.plist
  - **/*.entitlements
  - **/*.pbxproj
- 不新增 target/build settings
- 不触碰 watch/widget/config

Acceptance:
- Session Boundary：按 docs/SPEC.md（SPEC-LOCK）定义的会话开始/结束规则与会话 ID 稳定性。
- UI Rules：每会话一个卡片/cell；会话内早→晚；会话之间最新在上（允许 reversed 渲染）。
- Aggregation & Dedup：关键节点≤3条（拍摄开始/选片开始/结束）；重复/乱序事件只更新节点时间或忽略，不得新增行。
- Manual Acceptance Tests：A/B/C 必须在真机跑，exec.md 标注 PASS/FAIL（可附简述/截图）。
- 运行护栏：`bash scripts/ios_safe.sh --clean-deriveddata` PASS（提交/PR 前贴结果）。

Guardrails:
- 默认禁止修改 watch/widget 代码、Info.plist、project.pbxproj、entitlements、targets/appex 配置。
- 任何必须触碰配置的工作必须单独开“配置卡”，并贴 preflight 输出。
- 每次提交/PR 前必须跑并贴结果：`bash scripts/ios_safe.sh --clean-deriveddata`。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新
- STOP

## DONE — TC-IOS-HOME-SESSION-DURATIONS-V1
ID: TC-IOS-HOME-SESSION-DURATIONS-V1
Status: DONE (merged in PR #71)

## DONE — TC-IOS-STATS-MVP-V1
ID: TC-IOS-STATS-MVP-V1
Status: DONE (merged in PR #73)

## DONE — TC-IOS-STATS-RANGE-V1
ID: TC-IOS-STATS-RANGE-V1
Status: DONE (merged in PR #75)

## DONE — TC-IOS-STATS-METRICS-V1
ID: TC-IOS-STATS-METRICS-V1
Status: DONE (merged in PR #77)

## DONE — TC-IOS-HOME-SESSION-KEYMETRICS-V1
ID: TC-IOS-HOME-SESSION-KEYMETRICS-V1
Status: DONE (merged in PR #79)

## DONE — TC-IOS-STATS-BIZSUM-V1
ID: TC-IOS-STATS-BIZSUM-V1
Status: DONE (merged in PR #81)

## ACTIVE — TC-IOS-HOME-TODAY-BANNER-V1
ID: TC-IOS-HOME-TODAY-BANNER-V1
Title: Home 今日小看板（突出今日收入）
AssignedTo: Executor

Goal:
- Home 顶部新增紧凑“今日小看板”，突出今日收入，其它信息弱化为辅助。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Definitions:
- 仅“今日”范围，按 shootingStart 归属今日（沿用现有 ISO 规则）。
- 汇总来源复用 BizSum 的同一套数据（sessionSummaries + sessionId meta）。

Acceptance:
- Home 顶部出现 Banner（紧凑，2 行 + 可选第 3 行）。
- 第一行（主视觉）：文案“今日收入”，数值 `¥XXXX` 大号加粗；若无 amount 显示 `--`。
- 第二行（次要信息，浅色小字）：`今日单数 N单 · 今日总时长 X`。
- 第三行（可选，secondary）：`拍 Y · 选 Z · 拍摄张数 S · 选片张数 K · 选片率 R`（不抢主视觉）。
- 点击 Banner 跳转到 Stats（默认今日）。
- 缺失值：收入无记录显示 `--`，其它字段可 `--` 或省略（实现任选其一）。

Manual Verification:
- A：有金额数据时，收入正确且最显眼。
- B：金额缺失时显示 `--`，其它行不影响展示。
- C：新增/结束一单并填写金额后，收入更新。
- D：`bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP
