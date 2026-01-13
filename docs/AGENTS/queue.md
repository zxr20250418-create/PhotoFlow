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

## ACTIVE — TC-WATCH-DEBUG-UI-CLEANUP
ID: TC-WATCH-DEBUG-UI-CLEANUP
Title: 清理/隐藏 watch 端 Debug UI（保留隐藏入口）
AssignedTo: Executor

Goal:
- watch 端主界面不再出现任何明显的 Debug 按钮/入口（包括 Sync Diagnostics / DEBUG 文案入口）
- Debug 功能仍可访问，但必须是“隐藏入口”（例如：长按、连点、滚到最底部一个很小的 Debug 行）
- Release/正常使用路径完全不出现 Debug UI

Scope (Allowed files ONLY):
- `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`
- `docs/AGENTS/exec.md`（追加记录）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件
- 不改同步协议/业务逻辑，只改 UI 入口展示方式

Implementation requirements:
1) 所有 Debug UI 必须置于 `#if DEBUG` 下，且默认隐藏：
   - 例如：仅在“页面最底部”显示一个小的 Debug 入口
   - 或者需要 5 次连点标题才显示 Debug 入口
2) 保留诊断功能，但入口必须不可误触（明确记录入口动作）
3) 入口隐藏方式必须写入 `docs/AGENTS/exec.md`（让未来你自己能找到）

Acceptance:
- watch 主界面默认不显示 Debug 按钮
- 在 Debug 构建中按隐藏入口可以打开诊断面板/信息
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- `docs/AGENTS/exec.md` 写明：隐藏入口步骤 + 验证结果

StopCondition:
- PR opened to main（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新
- STOP
