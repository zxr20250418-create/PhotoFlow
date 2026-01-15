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

## DONE — TC-IOS-HOME-TODAY-BANNER-V1
ID: TC-IOS-HOME-TODAY-BANNER-V1
Status: DONE (merged in PR #83)

## DONE — TC-IOS-STATS-EFFICIENCY-V1
ID: TC-IOS-STATS-EFFICIENCY-V1
Status: DONE (merged in PR #85)

## DONE — TC-IOS-HOME-SESSION-CARD-SCAN-V1
ID: TC-IOS-HOME-SESSION-CARD-SCAN-V1
Status: DONE (merged in PR #87)

## DONE — TC-IOS-STATS-AVGSELRATE-EXCLUDE-ALLTAKE-V1
ID: TC-IOS-STATS-AVGSELRATE-EXCLUDE-ALLTAKE-V1
Status: DONE (merged in PR #89)

## DONE — TC-IOS-STATS-TOP3-V1
ID: TC-IOS-STATS-TOP3-V1
Status: DONE (merged in PR #91)

## DONE — TC-IOS-DAILY-REVIEW-DIGEST-V1
ID: TC-IOS-DAILY-REVIEW-DIGEST-V1
Status: DONE (merged in PR #93)

## DONE — TC-IOS-HOME-SESSION-DETAIL-V1
ID: TC-IOS-HOME-SESSION-DETAIL-V1
Status: DONE (merged in PR #95)

## ABANDONED — TC-IOS-DATA-QUALITY-V1
ID: TC-IOS-DATA-QUALITY-V1
Status: ABANDONED (Stats 卡住，相关 PR 已关闭未合并)

## DONE — TC-IOS-SHIFT-TIMELINE-V1
ID: TC-IOS-SHIFT-TIMELINE-V1
Title: 上班→下班时间线（工作/空余）
AssignedTo: Executor
Status: DONE (merged in PR #101)

Goal:
- Stats（今日）展示上班时间线与工作/空余总时长及利用率。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Definitions:
- shiftStart = onDutyAt；shiftEnd = offDutyAt（未下班用 now）。
- session intervals = [shootingStart, endedAt]（未结束用 now）。
- 裁剪到 [shiftStart, shiftEnd] 后做 union merge。
- workTotal = union length；idleTotal = (shiftEnd - shiftStart) - workTotal；利用率 = workTotal / (shiftEnd - shiftStart)。

Acceptance:
- Stats 今日新增“上班时间线”，展示上班/下班时间、工作/空余/利用率。
- 时间线条：深色=工作，浅色=空余。
- 工作段列表可选（若有，支持进入单子详情页）。

Manual Verification:
- A：上班→下班时间线显示正确（未下班实时更新）。
- B：工作/空余总时长与利用率合理（多单合并不重复）。
- C：工作段列表可跳转详情页（若实现）。
- D：`bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-SESSION-BACKFILL-FIXTIME-V1
Status: DONE (merged in PR #103)
ID: TC-IOS-SESSION-BACKFILL-FIXTIME-V1
Title: 补记一单 + 更正时间（覆盖统计与时间线）
AssignedTo: Executor

Goal:
- 支持补记一单（manual session）与更正时间（time override），并确保所有统计/时间线使用修正后的时间。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- 补记一单入口：Stats（今日）上班时间线 section 下方按钮“补记一单”。
- 补记表单字段：shootingStart、endedAt、selectingStart(可选)、amount、shotCount、selectedCount、reviewNote。
- 校验：shootingStart < endedAt；selectingStart 若存在需在区间内。
- 保存后：Home 列表可见，计入 Stats 汇总、Top3、上班时间线。
- 更正时间入口：SessionDetailView 按钮“更正时间”，可编辑 shootingStart/selectingStart/endedAt。
- 必须支持“恢复自动/清除更正”。
- 统计/时间线使用“有效时间”：override 优先，否则原始时间。
- 持久化：SessionTimeOverrideStore + manualSessions（按 sessionId）。

Acceptance:
- 补记后：Home/Stats 都可见，且计入今日汇总与上班时间线工作段。
- 更正时间后：Stats/上班时间线按新时间更新；清除更正可恢复原始时间。
- 重启后数据仍存在（持久化 OK）。
- `bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：补记一单保存后，Home/Stats 都能看到，且计入今日汇总与上班时间线工作段。
- B：更正时间后，Stats/上班时间线按新时间更新。
- C：清除更正后回到原始时间（统计随之恢复）。
- D：补记/更正数据重启后仍存在。
- E：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-DATA-QUALITY-V2
Status: DONE (merged in PR #106)
ID: TC-IOS-DATA-QUALITY-V2
Title: Stats 数据质量（缺失/异常提示，支持直达编辑）
AssignedTo: Executor

Goal:
- 在 Stats（今日/本周/本月范围）新增“数据质量”区块：展示缺失/异常计数，并列出具体单子；点击条目进入 SessionDetail 补填。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- 范围口径：复用 Stats 现有 segmented 的范围过滤（按 shootingStart 归属范围，ISO 周一规则保持一致）。
- 缺失项：amount 为空；shotCount 为空或 <=0；selectedCount 为空；reviewNote trim 后为空。
- 异常项：selectedCount > shotCount；总时长 == 0（或不可算）。
- 全要单不算异常：shotCount>0 && selectedCount==shotCount。
- UI：Stats 新增 section“数据质量”，顶部摘要“缺失 X · 异常 Y”，下方列出缺失/异常条目。
- 交互：点击条目跳转 SessionDetailView，便于补填/纠错。

Acceptance:
- 切换今日/本周/本月时，缺失/异常计数与列表随范围变化。
- 列表能显示“第N单 HH:mm：缺金额/缺拍/缺选/缺备注 …”或“选片>拍摄”等简要说明。
- 在详情页补填后返回 Stats，计数/列表实时更新；重启后仍正确。
- `bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：Stats 在今日/本周/本月切换时，缺失/异常计数同步变化。
- B：缺失/异常列表能列出具体单子；点击可跳到详情页。
- C：在详情页补填后返回 Stats，计数/列表即时更新；重启后仍正确。
- D：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-DUTY-MAINBUTTON-V1
Status: DONE (merged in PR #106 / #107; duty control + queue advance)
ID: TC-IOS-DUTY-MAINBUTTON-V1
Title: 上班并入中间主按钮
AssignedTo: Executor

Goal:
- 未上班时中间按钮显示“上班”；上班后显示下一步动作；下班入口移到长按菜单。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-SHIFT-CALENDAR-V1
Status: DONE (merged in PR #109)
ID: TC-IOS-SHIFT-CALENDAR-V1
Title: 月历记录（每日收入 + 上班时长）& 上下班时间可补记/更正
AssignedTo: Executor

Goal:
- 提供月历视图：每天格子显示“收入 + 上班时长”。
- 支持忘记下班/时间不准的补记与更正（可编辑上下班时间）。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- 新增 ShiftRecordStore（UserDefaults JSON）：records[YYYY-MM-DD] = {startAt, endAt}。
- setDuty(true) 写入 startAt（空则写 now）；setDuty(false) 写入 endAt=now；可双写旧 pf_shift_start/pf_shift_end。
- 上班时长按日裁剪：dayWindow = [day 00:00, nextDay 00:00]。
- duration = max(0, min(endAt ?? now, dayEnd) - max(startAt, dayStart))。
- Stats 顶部按钮“记录（月历）”进入 CalendarView（不新增 tab）。
- 月历：顶部年月切换，网格显示“收入 + 上班时长”，进行中显示角标。
- 本月汇总：本月收入 + 本月上班时长。
- 选中日明细：上班/下班/上班时长 + 编辑与补下班。
- 浮动“+”：补记当天班次 startAt/endAt。
- 文案统一“上班时长”（不再用“在岗时间”）。

Acceptance:
- 进入月历可切月；每天格子显示收入与上班时长。
- 编辑/补下班后，上班时长与本月汇总实时更新。
- `bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：Stats 点击“记录（月历）”进入月历；可切月。
- B：月历每天格子显示“收入 + 上班时长”；本月汇总正确。
- C：编辑某天上班/下班时间后，上班时长与本月汇总联动更新。
- D：忘点下班时可补下班。
- E：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP
