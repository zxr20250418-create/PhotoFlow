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

## PAUSED — TC-WIDGET-STATE-WRITE-FIX
ID: TC-WIDGET-STATE-WRITE-FIX
Status: PAUSED (spec alignment priority)

## ACTIVE — TC-SPEC-V1-ALIGNMENT
ID: TC-SPEC-V1-ALIGNMENT
Title: 更新 SPEC：v1 纳入 watch/widget（对齐现实，删除过期约束）
AssignedTo: Executor

Goal:
- `docs/SPEC.md` 增加 v1 小节：明确 watch app + widget/complication 已纳入范围与当前约束
- 将 “v0: watch must NOT include Complication/WidgetKit” 标注为历史阶段（v0 已结束），不再作为现行约束

AllowedFiles (ONLY):
- `docs/SPEC.md`
- (optional) `docs/AGENTS/exec.md`（记录此次文档更新摘要）

Forbidden:
- 不改任何代码、脚本、配置文件
- 不改 queue 以外的文档（除非确实需要在 `docs/RELEASE_CHECKLIST.md` 里补一句 gate）

Acceptance:
- `docs/SPEC.md` 明确包含：
  1) v0（历史）：当时的边界与为何这么定
  2) v1（现行）：当前包含 watch app + widget/complication + phone↔watch sync + diagnostics
  3) 现行默认规则：Swift-only 卡默认不允许改 `Info.plist`/`project.pbxproj`；只有“配置卡”才允许，并必须跑 preflight/embedded checks
- PR opened and merged (docs-only)
- STOP
