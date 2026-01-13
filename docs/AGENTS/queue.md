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

## ACTIVE — TC-COMPLICATION-TAP-OPEN-APP
ID: TC-COMPLICATION-TAP-OPEN-APP
Title: 表盘 Complication 点开默认打开 App（支持 circular/corner/rectangular）
AssignedTo: Executor

Goal:
- 支持三种 complication family：`accessoryCircular` / `accessoryCorner` / `accessoryRectangular`
- 点击表盘 complication 后，系统默认打开 PhotoFlow Watch App（不要求跳到指定页面）
- 不引入任何深链/URL scheme 依赖（不碰 DL-3）

Scope (Allowed files ONLY):
- `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift`
- `docs/AGENTS/exec.md`（追加记录）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件
- 不改业务同步逻辑（只改 widget 显示与点击行为）

Implementation requirements:
1) 绝对禁止为 complication 设置 `widgetURL`：
   - 不允许 `.widgetURL(...)`
   - 不允许 `Link(destination:)` 包裹视图
   目的：让点击行为回到系统默认“打开宿主 App”。
2) 三种 family 均保持可用：
   - `supportedFamilies` 必须包含：circular + corner + rectangular
   - 三种布局可不同，但都必须能正常预览/编译/显示

Acceptance:
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- 手动验证（写入 `docs/AGENTS/exec.md`）：
  - 在 Watch 表盘添加三种 complication
  - 点击任意一种 complication：能打开 PhotoFlow Watch App（默认入口），不闪退、不弹错误

StopCondition:
- PR opened to `main`（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新（包含验证步骤/结果）
- STOP
