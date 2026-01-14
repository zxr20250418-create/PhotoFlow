# PhotoFlow Spec

## Targets
- iOS App: PhotoFlow
- watchOS: yes
  - If yes: Watch App target(s) are created by Xcode’s “Watch App for iOS App” template.

## v0 (HISTORICAL, not current)
- v0 watch excluded complication/widgetkit to reduce scope and target wiring risk during initial watch setup.
- Time window: Dec 2025–Jan 2026 (initial watch target bring-up).

## v1 (CURRENT)
- Scope includes: watch app, widget/complication, phone↔watch sync (V1/V2), diagnostics/status banner, complication tap-to-open app.
- Guardrails: iOS-only workflow uses `bash scripts/ios_safe.sh --clean-deriveddata`.
- High-risk changes (Info.plist/pbxproj/entitlements) only via “config cards” with strict preflight outputs required.

### iOS Home Timeline Spec Lock (TC-IOS-HOME-TIMELINE-SPEC-LOCK)

#### A) Session Boundary (会话/一单边界)
- 会话开始：第一次进入 `shooting`（或 StartShooting）时创建/进入当前会话。
- 会话结束：进入 `ended`（或 End），或 reset/off duty 导致会话清空时结束。
- 会话 ID：优先复用现有 session/sync id；否则用会话开始时间戳生成并在会话结束前保持不变。

#### B) UI Rules（展示规则）
- 入口：iOS 首页一个区块（不大改首页结构）。
- 列表按“会话”展示：每会话一个卡片/cell（不是事件列表）。
- 会话内部：早→晚。
- 会话之间：最新在上（允许 reversed 渲染）。

#### C) Aggregation & Dedup（聚合/去重，核心）
- 会话内只呈现关键节点（建议≤3条）：拍摄开始 / 选片开始 / 结束。
- 明确禁止 raw append：不得把每次 stage 切换当作一条日志新增（禁止同秒刷屏）。
- 重复/乱序事件：只能更新对应节点时间或忽略，不得新增行。

#### D) Manual Acceptance Tests（手动验收）
- 用例 A：iPhone 拍摄→选片→结束：仅 1 个会话卡片，≤3 行，无刷屏。
- 用例 B：本地 + watch 回传（重复/乱序）：仍 1 个会话卡片，不新增行。
- 用例 C：连续两单：2 个会话卡片，新会话在上，内部顺序正确（早→晚）。

### Gates (config cards)
- exec.md must include: `preflight_build.sh` / `ios_safe.sh` output.
- exec.md must include: embedded widget appex check.
- exec.md must include: embedded watch app/watchkit extension check.

## Bundle Identifiers
- iOS: com.zhengxinrong.PhotoFlow
- watchOS (if any): derived from iOS bundle id by Xcode; keep consistent and documented after creation.

## Minimum Deployment
- iOS: 17.0
- watchOS (if any): 10.0

## Versioning Rules (Hard)
- MARKETING_VERSION starts at `0.1.0`
- CURRENT_PROJECT_VERSION (Build) starts at `1`
- **All targets must always share the same MARKETING_VERSION and Build**

## Local Build
- iOS build:
  - `bash scripts/check_versions.sh`
  - `bash scripts/build_ios.sh`
- watch build (if enabled):
  - `bash scripts/build_watch.sh`

## Release (TestFlight)
- Bump Build:
  - `bash scripts/bump_build.sh`
  - commit: `chore(build): bump build`
- Verify:
  - `bash scripts/check_versions.sh`
  - `bash scripts/build_ios.sh` (+ watch if enabled)
- Archive & Upload via Xcode Organizer (or xcodebuild archive later, if introduced)
- Tag after successful upload:
  - `git tag -a v${MARKETING_VERSION}+${BUILD} -m "Release v${MARKETING_VERSION}+${BUILD}"`
  - `git push --tags`
