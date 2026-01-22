## DONE — TC-IOS-AI-MODEL-PICKER-V1
Status: DONE (merged in PR #190)
Priority: P0
Goal:
- Settings 增加 provider+model+reasoning.effort 选择
- “连接已测试”按 (provider, model, effort) 维度记录
- AI 校验请求使用当前选中的 model/effort

Scope:
- OpenAI models:
  - GPT-5.2 Thinking -> gpt-5.2
  - GPT-5.2 Instant -> gpt-5.2-chat-latest
  - GPT-5.2 Pro -> gpt-5.2-pro
- Reasoning effort (OpenAI only): none/low/medium/high/xhigh
- Claude: 维持现状（无 effort）
- 连接测试与 AI 校验必须绑定同一个 key（provider, model, effort）

Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- Forbidden: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget config
- Must run: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
A Settings 可选择 model 与 effort，重启后仍保留
B 连接测试状态按 (provider,model,effort) 缓存，切换模型后状态正确变化
C AI 校验使用当前 model/effort；未测试时明确提示先测试
D ios_safe PASS；0 配置改动

## DONE — TC-IOS-AI-REVIEW-CHECKER-V1
Status: DONE (merged in PR #188)
Priority: P0
Goal:
- AI 校验 5 槽位是否合格 指出哪段不合格 给重写指令
Scope:
- 在单子详情页或编辑指标页增加按钮：AI 校验
- 输入：Facts Decision Rationale OutcomeVerdict NextDecision + 自动指标快照（收入 拍摄时长 选片时长 RPH(拍+选) 选片率）
- 输出并落盘：
  score 0 到 10
  perFieldPass（Facts Decision Rationale OutcomeVerdict NextDecision）
  rewriteInstructions（仅对不合格字段给一句重写要求）
  blindspot（可选一句话）
- 结构化输出必须固定 schema
- V1 仅支持手动点击触发 不自动跑
Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- Forbidden: Info.plist project.pbxproj entitlements targets appex watch widget config
- Must run: bash scripts/ios_safe.sh --clean-deriveddata
Acceptance:
A 点 AI 校验后能得到 score 与每段 PASS FAIL
B 对 FAIL 段给出一条重写指令 且只针对 FAIL 段
C 保存后重启仍存在 且多端同步可见
D ios_safe PASS 0 配置改动

## DONE — TC-IOS-API-CONNECTIVITY-BADGE-V1
Status: DONE (merged in PR #186)
Priority: P1
Goal:
- 增加“连接已测试”状态，明确 API 是否可用（例如 openai 与 Claude）
Scope:
- Settings 页展示 badge + lastTestAt + lastError
- 测试按钮触发 health check（10 秒超时）
- 可选自动测试：app active 且 lastTestAt 过期时自动跑一次
Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- Forbidden: Info.plist project.pbxproj entitlements targets appex watch widget config
- Must run: bash scripts/ios_safe.sh --clean-deriveddata
Acceptance:
A 有效 key 测试后显示 ✅ 连接已测试 且时间更新
B 无效 key 或断网显示 ❌ 测试失败 且错误摘要可读
C 冷启动后仍能看到上次状态
D ios_safe PASS 0 配置改动

## DONE — TC-IOS-SESSION-5SLOT-REVIEW-V1
Status: DONE (merged in PR #184)
ID: TC-IOS-SESSION-5SLOT-REVIEW-V1
Title: 单子详情页 5 槽位复盘 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- 单子详情页新增 5 槽位复盘（Facts/Decision/Rationale/Outcome/NextDecision），手动输入并持久化，同步三端。

Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 详情页可折叠展开 5 槽位，收起显示摘要
- 输入后离开/冷启动仍可见
- iPhone 修改后 iPad 同步可见
- ios_safe PASS；0 配置改动

## PAUSED — TC-PREFLIGHT-EMBEDDED-WATCHAPP
ID: TC-PREFLIGHT-EMBEDDED-WATCHAPP
Status: PAUSED (postponed; return after stability restored)

## ABANDONED — TC-DEEPLINK-DL3-SCHEME
ID: TC-DEEPLINK-DL3-SCHEME
Status: ABANDONED (rollback; PR #33 closed)

## PAUSED — TC-WIDGET-TAP-OPEN-APP
ID: TC-WIDGET-TAP-OPEN-APP
Status: PAUSED (superseded by sync priority)

## DONE — TC-IOS-DUTY-STATE-RESUME-FIX
Status: DONE (merged in PR #181)
ID: TC-IOS-DUTY-STATE-RESUME-FIX
Title: 上班状态前后台恢复修复
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- 上班状态由 ShiftRecord 持久化推导，前后台/冷启动不回到未上班。

Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 前后台切换仍显示已上班
- 冷启动仍能恢复已上班
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-TIMELINE-SCROLL-STABILITY-V1
Status: DONE (merged in PR #179)
ID: TC-IOS-TIMELINE-SCROLL-STABILITY-V1
Title: Home timeline scroll stability
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- 修复自动滚动干扰手动滚动，恢复左滑删除/作废。

Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 手动滑到底部不跳动
- 新增会话仅在 near-bottom 且非拖动时自动滚动
- 左滑删除/作废可见
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-HOME-TOMORROW-ACTION-BANNER-V1
Status: DONE (merged in PR #177)
# TC-IOS-HOME-TOMORROW-ACTION-BANNER-V1
Priority: P1
Goal:
- Home 顶部日期下方 备忘框上方显示 明天唯一动作
- 次日自动承接到 DayMemo 仅当 DayMemo 为空时

Scope:
- Banner: tomorrowOneAction 非空才显示
- Cross-day: app active 检测跨天
  若 today DayMemo.text 为空 且 yesterday tomorrowOneAction 非空
  自动写入 today DayMemo.text = yesterday tomorrowOneAction 并保存
  若 today DayMemo 已有内容 绝不覆盖

Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- Forbidden: Info.plist project.pbxproj entitlements targets appex watch widget config
- PR before: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
A 修改复盘详情 tomorrowOneAction 回到 Home 立即可见
B 跨天 today memo 为空才自动承接 不为空不覆盖
C ios_safe PASS 0 配置改动

## DONE — TC-IOS-DAILY-REVIEW-V1_1-RPHWORK-SEARCH
Status: DONE (merged in PR #173)
ID: TC-IOS-DAILY-REVIEW-V1_1-RPHWORK-SEARCH
Title: 复盘 RPH 口径调整 + 复盘记录搜索与按月筛选 V1.1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- RPH 按拍摄+选片总时长口径计算；复盘记录支持搜索与按月筛选。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift

Guardrails:
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- RPH = 收入 / (拍摄总时长 + 选片时长)，收入为空或分母为 0 显示 --
- Bottom1（最低 RPH）按新口径计算
- 复盘记录支持搜索（dayKey / tomorrowOneAction / notesAll / bottom1Note）
- 复盘记录支持按月筛选，默认当前月，先月筛选再搜索过滤
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-IPAD-DASHBOARD-V1
Status: DONE (merged in PR #152)
ID: TC-IOS-IPAD-DASHBOARD-V1
Title: iPad 统计看板增强 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- iPad 只读看板：今日 KPI + Top3（收入）+ 会话详情。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift

Guardrails:
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 默认范围：今日（每次进入回到今日）
- Top3 默认按收入降序
- iPad 只读（不做编辑）
- 不引入启动重计算，不把重计算放 View body 同步执行
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-IPAD-DASHBOARD-RANGE-V1_1
Status: DONE (merged in PR #154)
ID: TC-IOS-IPAD-DASHBOARD-RANGE-V1_1
Title: iPad 看板范围切换 V1.1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- 增加范围切换：今日 / 本周 / 本月（默认仍为今日）。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift

Guardrails:
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 增加范围切换：今日 / 本周 / 本月（默认仍为今日）
- KPI 仅显示 3 项：收入 / 单数 / 总时长
- Top3 按收入排序，并随范围变化
- 不做图表，不改数据模型
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-IPAD-DASHBOARD-BOTTOM1-V1
Status: DONE (no open implementation PR found; skipped merge step)
ID: TC-IOS-IPAD-DASHBOARD-BOTTOM1-V1
Title: iPad 看板 Bottom1 提示 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- iPad 看板新增 Bottom1（最大损耗源），范围同步（今日/本周/本月），每天只提示一个最差点。

Scope:
- 在 iPad 看板 KPI/Top3 下方新增 Bottom1 卡片（只显示 1 条）
- Bottom1 默认按“最低 RPH（收入/总时长）”筛选
- 若收入为空或总时长为 0：跳过该单（避免噪音）
- 点击 Bottom1 跳到该会话详情（只读）

Guardrails:
- Allowed files: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 默认显示 Bottom1（最低 RPH），并随范围切换同步变化
- Bottom1 的计算不放在启动同步路径里，不引入卡顿
- 点击可跳到会话详情
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-SESSION-DELETE-TOMBSTONE-FIX
Status: DONE (merged in PR #158)
ID: TC-IOS-SESSION-DELETE-TOMBSTONE-FIX
Title: 会话删除/作废 Tombstone 修复
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- 删除/作废走 tombstone 与去重过滤，避免 CloudKit 回滚复活。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift

Guardrails:
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- Swipe 删除/作废立即从列表消失，重启不复活
- iPhone 删除后 iPad 60 秒内消失
- 详情页仅展示状态，无 destructive 操作
- ios_safe PASS；0 配置改动

## PAUSED — TC-IOS-IPAD-STAGE-ACTIONS-V1
Status: PAUSED (superseded by TC-IOS-IPAD-STAGE-ACTIONS-FINAL-V1)
ID: TC-IOS-IPAD-STAGE-ACTIONS-V1
Title: iPad 阶段推进 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- iPad 端可推进阶段（开始拍摄/选片/结束），iPhone 为权威写入端。

Scope:
- iPad UI 提供阶段按钮并显示 pending
- iPad 写 StageEvent（可离线保存）
- iPhone 监听 StageEvent（CloudKit remote change）串行消费并写 canonical SessionRecord，同步至 watch/iPad

Guardrails:
- Allowed files: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- iPad 在线推进 -> iPhone + watch 对齐 <=10s，pending 清除
- iPad 离线推进 -> pending 显示；恢复后 <=60s 对齐并清 pending
- 旧动作不回滚 canonical（revision 规则生效）
- 启动不卡/白屏
- ios_safe PASS；0 配置改动

## PAUSED — TC-IOS-IPAD-STAGE-ACTIONS-FINAL-V1
Status: PAUSED (iPad 阶段推进复杂度过高，暂不投入；iPad 维持只读看板 + DayMemo 编辑)
ID: TC-IOS-IPAD-STAGE-ACTIONS-FINAL-V1
Title: iPad 阶段推进收口 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- iPad 阶段推进稳定收敛；iPhone 仍为权威写入端。

Scope:
- iPad 写 StageEvent（可离线保存）；UI 显示 pending
- iPhone 串行消费 StageEvent 并写 canonical SessionRecord（revision 递增）
- 事件结果写 processedAt + processedResult (acked/rejected)，iPad 依据结果清 pending
- iPhone 前台时主动处理事件队列并更新 watch/iPad

Guardrails:
- Allowed files: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- iPad 在线推进 -> iPhone + watch 对齐 <=10s，pending 清除
- iPad 离线推进 -> pending 显示；恢复后 <=60s 对齐并清 pending
- 旧/冲突动作被 rejected 且不回滚 canonical
- 诊断字段可见：pendingEventCount / oldestPendingEventAge / lastProcessedEventAt / lastProcessError
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-HOME-TIMELINE-TODAY-ONLY-V1
Status: DONE (merged in PR #163)
ID: TC-IOS-HOME-TIMELINE-TODAY-ONLY-V1
Title: Home 会话时间线仅今日展示 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- Home 会话时间线只显示今天的会话；历史会话仅在“记录/月历/iPad 看板”查看。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift

Guardrails:
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- Home 会话时间线只显示今天的会话
- 历史会话不在 Home 显示，但在“记录/月历/iPad 看板”仍可见
- 跨天进行中的单仍显示在 Home 顶部
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-HOME-DAYMEMO-TOGGLE-V1
Status: DONE (merged in PR #168)
ID: TC-IOS-HOME-DAYMEMO-TOGGLE-V1
Title: Home 顶部备忘点日期展开收起 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- Home 顶部备忘默认隐藏；点击日期展开/收起；内容保留。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift

Guardrails:
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 默认不显示备忘区域，不占空白
- 点击日期展开备忘，再点收起且内容保留
- 备忘位于日期下方、收入卡上方
- ios_safe PASS；0 配置改动

## DONE — TC-IOS-DAILY-REVIEW-GENERATE-V1
Status: DONE (merged in PR #170)
ID: TC-IOS-DAILY-REVIEW-GENERATE-V1
Title: 生成今日复盘卡并持久化 V1
AssignedTo: Coordinator1/Codex
Priority: P1

Goal:
- 主动点“生成今日复盘”才生成；自动汇总 Top3/Bottom1 与关键指标；持久化保存；你只需填“明天唯一动作”。

Scope:
- 按钮：生成今日复盘（主动点击）
- 持久化 DailyReview（按 dayKey upsert，保留已有 tomorrowOneAction）
- 展示：复盘详情页 + 历史列表
- 自动指标：income / shootingTotal / selectingTotal / RPHshoot / sessionCount / Top3(收入) / Bottom1(最低 RPHshoot)
- 自动备注汇总：bottom1Note + notesAll（最小可用）

Guardrails:
- Allowed: PhotoFlow/PhotoFlow/**/*.swift
- （如需新增 DailyReview 实体）允许改 .xcdatamodeld，但不得 unique constraints，属性需 optional 或有 default
- 禁止：Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑：bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
- 点击生成后出现今日复盘详情页
- Top3/Bottom1 与今日范围一致，Bottom1=最低 RPHshoot
- “明天唯一动作”可编辑并持久化
- 历史列表可查看过去生成的复盘
- ios_safe PASS；0 配置改动

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

## DONE — TC-IOS-HOME-HEADER-CLEANUP-V1
Status: DONE (merged in PR #132)
ID: TC-IOS-HOME-HEADER-CLEANUP-V1
Title: Home 固定区 UI 优化（收入卡精简 + 备忘折叠）
AssignedTo: Executor

Goal:
- 今日收入卡只显示三项，并支持可选显示本月/本年收入。
- 备忘使用折叠卡方案 A：主页预览两行，编辑时弹出 sheet。
- 顶部固定区不随滚动，时间线列表可滚动。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- 今日收入卡默认显示三项：今日收入 / 今日单数 / 今日总时长。
- 可选显示：本月收入 / 本年收入（默认隐藏；卡内小按钮展开后可切换）。
- 备忘折叠卡：默认两行预览 + 编辑按钮；编辑弹出 sheet 保存后回到两行预览。
- 仅会话时间线列表可滚动；固定区不滚动。

Acceptance:
- A：今日收入卡只显示三项（默认态）。
- B：本月/本年收入可隐藏/显示（默认隐藏）。
- C：备忘两行预览 + 编辑 sheet 保存生效，重启仍保留。
- D：时间线可滚动，顶部固定区不随滚动，底部按钮可点。
- E：`bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：Home 顶部今日收入卡只显示 今日收入/单数/总时长。
- B：本月收入、本年收入可隐藏/显示（默认隐藏；展开后可开关）。
- C：备忘默认两行预览；编辑保存后回到预览，重启仍保留。
- D：会话时间线可滚动；顶部固定区不随滚动；底部按钮可点。
- E：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-WATCH-UI-V1
Status: DONE (merged in PR #134)
ID: TC-WATCH-UI-V1
Title: Watch 端 UI 重做 v1（更顺手/更清晰/可诊断）
AssignedTo: Executor

Goal:
- Watch 主屏操作顺手、阶段清晰、可诊断 lastSync。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlowWatch Watch App/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata --allow-watch-swift`。

Requirements:
- 主屏：阶段大标题 + 主按钮（下一步动作）+ 两行时长 + lastSyncAt（淡）。
- 未上班：主按钮为“上班”，仍显示 lastSyncAt。
- 长按主按钮菜单：立即同步、下班（上班中时）、补记最近一单（可先占位）。
- 时长基于时间戳计算；点亮/进入前台先 pull latest 再渲染。

Acceptance:
- A：阶段/按钮符合预期，操作顺手。
- B：lastSyncAt 刷新，“立即同步”可用。
- C：锁屏点亮后不显示旧阶段。
- D：`bash scripts/ios_safe.sh --clean-deriveddata --allow-watch-swift` PASS；0 配置文件改动。

Manual Verification:
- A：watch 主屏阶段/按钮符合预期，操作顺手。
- B：lastSyncAt 能刷新；“立即同步”可用。
- C：锁屏点亮后不会显示旧阶段。
- D：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-SYNC-TRI-DEVICE-V1
Status: DONE (merged in PR #138)
ID: TC-SYNC-TRI-DEVICE-V1
Title: 三端同步 V1（iPhone 权威写入 + watch 事件上报 + ACK）
AssignedTo: Coordinator1/Codex

Goal:
- iPhone 成为唯一权威写入端；watch 事件上报后几秒内对齐显示。
- watch 事件带 ACK，断连可补发；iPad 先做本地只读入口（无 iCloud）。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- PhotoFlow/PhotoFlowWatch Watch App/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget 配置、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- CanonicalState：sessionId, stage, shootingStart, selectingStart, endedAt, revision(Int64), updatedAt, sourceDevice。
- revision 单调递增（毫秒时间戳为主），合并规则：revision 更大优先；相等用 sourceDevice tie-break。
- watch 只发事件（sessionId/action/clientAt/sourceDevice），2 秒未 ACK 进入 pending + outbox 重试。
- iPhone 串行处理事件并生成 canonical state，回 ACK（含 revision + canonical state）。
- 通道：sendMessage+reply 快 ACK；transferUserInfo 保底；updateApplicationContext 始终最新快照。
- Debug only：watch/iPhone 显示 lastSyncAt / pendingCount / lastRevision。
- iPad：本地只读入口（读本地 canonical store；无 iCloud 配置）。

Acceptance (Device):
- A：watch 点开始拍摄后，iPhone 2 秒内显示新阶段并按时间戳计时。
- B：watch 锁屏后点亮，对齐 iPhone 最新 canonical state，pending 消失。
- C：不可达时 watch 进入 pending；恢复连接后最终一致并清除 pending。
- D：iPhone 重启后状态仍正确（持久化生效）。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-IPAD-CLOUDSYNC-V1
Status: DONE (merged in PR #142)
ID: TC-IOS-IPAD-CLOUDSYNC-V1
Title: iPad 同步 + iCloud CloudKit V1
AssignedTo: Coordinator1/Codex

## DONE — TC-IOS-FILES-EXPORTIMPORT-V1_1
Status: DONE (merged in PR #144)
ID: TC-IOS-FILES-EXPORTIMPORT-V1_1
Title: Files 导入导出 V1.1
AssignedTo: Coordinator1/Codex

Priority: P1
Goal: 无 iCloud 模式补齐。支持 Files 导出/导入，按 revision 合并。

Scope:
- iPhone+iPad 都提供导出与导入入口
- 导出格式: JSON 或 zip(JSON)，包含 schemaVersion/exportedAt/deviceId/records
- 导入: 选择文件 -> 预览新增/更新/冲突数量 -> 确认 -> 按 revision 合并

Guardrails:
- Allowed files: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
A 导出到 Files 成功，可在 Files 看到文件
B 导入后数据可恢复，不重复写入
C 冲突合并: revision 大覆盖小；相等按 sourceDevice tie-break
D ios_safe PASS；0 配置改动

Manual Verification:
- iPhone 导出 -> iPad 导入后能看到同样记录
- iPad 导出 -> iPhone 导入后能看到同样记录

## DONE — TC-IOS-IPAD-DAYMEMO-EDIT-V1_1
Status: DONE (merged in PR #146)
ID: TC-IOS-IPAD-DAYMEMO-EDIT-V1_1
Title: iPad DayMemo 编辑 V1.1
AssignedTo: Coordinator1/Codex

Priority: P1
Goal: iPad 端仅开放 DayMemo 编辑，离线可编辑，联网后自动合并。

Scope:
- iPad DayMemo 可编辑保存
- 只做 DayMemo，不开放 Session 编辑
- 冲突策略: revision 大覆盖小，给轻提示即可

Guardrails:
- Allowed files: PhotoFlow/PhotoFlow/**/*.swift
- 禁止触碰: Info.plist / project.pbxproj / entitlements / targets / appex / watch / widget 配置
- PR 前必跑并贴: bash scripts/ios_safe.sh --clean-deriveddata

Acceptance:
A iPad 离线编辑 DayMemo 保存成功
B 联网后 iPhone 端出现更新（允许几十秒）
C 冲突按 revision 规则合并
D ios_safe PASS；0 配置改动

## DONE — TC-IOS-WIDGET-COMPLICATION-TIMER-V1
Status: DONE (merged in PR #149)
ID: TC-IOS-WIDGET-COMPLICATION-TIMER-V1
Title: Widget/Complication 计时实时走（不再卡 00:00）
AssignedTo: Executor

Goal:
- iOS 小组件与 watch complication 计时使用时间戳动态展示，阶段切换后能刷新。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlowWidget/**/*.swift
- PhotoFlow/PhotoFlowWatchWidget/**/*.swift
- PhotoFlow/PhotoFlow/ContentView.swift（仅触发 reload）
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata --allow-watch-swift`。

Requirements:
- 读取 App Group canonical state（stage + stageStartAt + revision）。
- 动态计时显示（timerInterval/relative 文本）；无 startAt 时显示占位。
- 状态变更时 reload timeline（WidgetCenter）。
- 不做重计算（不遍历 sessions）。

Acceptance:
- A：iOS 小组件计时会变化（不再卡 00:00）。
- B：complication 计时会变化。
- C：阶段切换后合理时间内刷新到新阶段并从新 startAt 计时。
- D：锁屏/后台再亮起仍正确。
- E：`bash scripts/ios_safe.sh --clean-deriveddata --allow-watch-swift` PASS；0 配置文件改动。

Manual Verification:
- A：iOS 小组件计时会变化（不再卡 00:00）。
- B：complication 计时会变化。
- C：阶段切换后合理时间内刷新到新阶段并从新 startAt 计时。
- D：锁屏/后台再亮起仍正确。
- E：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-SESSION-QUICK-LAST-V1
Status: DONE (merged in PR #120)
ID: TC-IOS-SESSION-QUICK-LAST-V1
Title: 一键补记/改记最近一单
AssignedTo: Executor

Goal:
- 提供一个“入口很浅”的快捷操作，能立刻补记/改记最近一单，减少漏填。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Definitions:
- 最近一单：当前 shift（上班→下班）范围内 effectiveEnd 最大的 session；effectiveEnd = endedAt ?? now。
- 若当前 shiftStart 不存在（未上班）：改为“今天”内 effectiveEnd 最大的 session。
- 若范围内无 session：改记最近一单置灰/隐藏，补记仍可用。

Requirements:
- 入口：底部中间主按钮长按菜单新增：
  - 补记最近一单
  - 改记最近一单（无最近一单则置灰/隐藏）
- 补记最近一单：弹出 sheet 表单（startAt/endAt/selectingStart/amount/shotCount/selectedCount/reviewNote）。
- 改记最近一单：同一 sheet，预填最近一单数据（时间 override 优先）。
- 保存后立即反映到 Home/Stats/Top3/上班时间线。

Acceptance:
- 长按主按钮出现“补记最近一单/改记最近一单”。
- 补记保存后：Home/Stats/时间线都出现并计入。
- 改记保存后：统计立即更新。
- 重启后仍存在（持久化 OK）。
- `bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：长按主按钮出现“补记最近一单/改记最近一单”。
- B：补记保存后，Home/Stats/时间线都出现并计入。
- C：改记保存后，统计立即更新。
- D：重启后仍存在（持久化 OK）。
- E：ios_safe PASS；0 配置文件改动。

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

## DONE — TC-IOS-HOME-FIXED-HEADER-MEMO-V1
Status: DONE (merged in PR #111)
ID: TC-IOS-HOME-FIXED-HEADER-MEMO-V1
Title: Home 顶部固定区（日期+今日收入+当日备忘）
AssignedTo: Executor

Goal:
- Home 顶部固定显示日期+今日收入+当日备忘输入框；会话时间线仅下方滚动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-SESSION-DELETE-VOID-V1
Status: DONE (merged in PR #113)
ID: TC-IOS-SESSION-DELETE-VOID-V1
Title: 删除 + 作废（对所有单）
AssignedTo: Executor

Goal:
- 在 SessionDetailView 支持作废/恢复与删除单子，并对所有统计/展示生效。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- 作废/恢复（可逆）：作废后该单不计入任何统计/展示；恢复后全部恢复。
- 删除（不可逆）：从 Home/Stats/Top3/上班时间线/备注汇总等彻底移除，并清理该 sessionId 的关联数据。
- 适配所有单：自动记录、补记/手动新增、时间更正后的单。
- 持久化：voidedSessionIds / deletedSessionIds（UserDefaults JSON）。
- 全局过滤：所有 session 列表与统计统一先排除 deleted/voided。
- 删除清理：清掉 meta、时间更正 override、manual/backfill 数据。
- 删除需二次确认；作废/恢复无需确认。

Acceptance:
- 作废后：该单从所有列表/统计消失；恢复后全部回来。
- 删除后：永久消失且相关 meta/更正/补记数据被清理。
- 重启后仍生效（持久化 OK）。
- `bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：作废/恢复能影响 Home/Stats/Top3/上班时间线等所有统计与列表。
- B：删除后永久移除并清理关联数据。
- C：重启后仍生效。
- D：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP

## DONE — TC-IOS-STATS-BOTTOM1-V1
Status: DONE (merged in PR #117)
ID: TC-IOS-STATS-BOTTOM1-V1
Title: Bottom1（最大损耗源）
AssignedTo: Executor

Goal:
- 在 Stats 增加 Bottom1（最大损耗源），随 今日/本周/本月 切换同步变化。

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlow/**/*.swift
- docs/AGENTS/exec.md（可选）

Guardrails:
- 禁止触碰：watch/widget、Info.plist、project.pbxproj、entitlements、targets/appex。
- PR 前必跑并贴：`bash scripts/ios_safe.sh --clean-deriveddata`。

Requirements:
- 范围口径：复用 Stats 现有 segmented 的范围过滤（按 shootingStart 归属范围，ISO 周一规则）。
- 统计需使用过滤后的 sessions + meta + 有效时间（override 优先）。
- Section：Bottom1（最大损耗源），包含四条：
  1) 最低 RPH：amount/(totalSeconds/3600)，过滤 amount 有值且 totalSeconds>0。
  2) 最耗时一单：totalSeconds 最大。
  3) 全要单中拍摄张数最大：shotCount>0 且 selected==shot。
  4) 最长空余段：复用上班时间线同一套 shift + work union 逻辑，取范围内最大 idle 间隔。
- 行展示建议：
  - 最低RPH：第N单 HH:mm · RPH ¥xxx/小时 · ¥amount · 用时 mm:ss
  - 最耗时：第N单 HH:mm · 用时 mm:ss · ¥amount（可选）
  - 全要最大：第N单 HH:mm · 全要 · 拍S张 · ¥amount（可选）；无则“全要：无”
  - 最长空余段：YYYY-MM-DD HH:mm–HH:mm · 空余 xxm；无 shift 则“空余：无”
- 点击行跳转 SessionDetailView（空余段除外）。

Acceptance:
- Bottom1 四条随范围切换同步变化（有数据时）。
- 结果符合直觉：最低RPH/最长用时/全要最大张数。
- 最长空余段显示合理（有 shift 时）。
- `bash scripts/ios_safe.sh --clean-deriveddata` PASS；0 配置文件改动。

Manual Verification:
- A：切换 今日/本周/本月，Bottom1 四条随范围同步变化。
- B：最低RPH/最长用时/全要最大张数符合直觉。
- C：最长空余段能显示且合理（有 shift 时）。
- D：ios_safe PASS；0 配置文件改动。

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 更新（若有）
- STOP
