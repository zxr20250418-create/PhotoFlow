## PAUSED — TC-PREFLIGHT-EMBEDDED-WATCHAPP
ID: TC-PREFLIGHT-EMBEDDED-WATCHAPP
Status: PAUSED (postponed; return after stability restored)

## ABANDONED — TC-DEEPLINK-DL3-SCHEME
ID: TC-DEEPLINK-DL3-SCHEME
Status: ABANDONED (rollback; PR #33 closed)

## PAUSED — TC-WIDGET-TAP-OPEN-APP
ID: TC-WIDGET-TAP-OPEN-APP
Status: PAUSED (superseded by sync priority)

## ACTIVE — TC-SYNC-PHONE-TO-WATCH-V1
ID: TC-SYNC-PHONE-TO-WATCH-V1
Title: 手机端操作同步到手表端（stage/计时状态）V1
AssignedTo: Executor

Goal:
- 手机端按“拍摄/选片/停止”（或对应动作）后，手表端 UI 在合理时间内同步更新。
- 不依赖 App Group 跨设备（App Group 只用于同设备：watch app ↔ widget）。
- 最终一致（表端不在前台也能收到），前台时尽量即时。

Scope (Allowed files ONLY):
- iPhone app：PhoneConnectivity / WCSession 管理相关 Swift 文件（当前 iOS 侧连接管理文件）
- Watch app：WatchConnectivityManager / WatchSyncStore / WCSession delegate 相关 Swift 文件
- （如需要）双方各自的 State Store 文件（但不新增 target/pbxproj）
- `docs/AGENTS/exec.md`（追加）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 禁止新增 URL scheme / deep link
- 禁止重构 UI，只改同步链路

Protocol / Implementation requirements:
1) iPhone→Watch 必须使用“双通道”：
   - Always: `updateApplicationContext(payload)` 作为最终一致
   - If reachable: `sendMessage(payload)` 作为即时刷新
2) Watch 端必须实现并处理：
   - `didReceiveApplicationContext`（最终一致）
   - `didReceiveMessage`（即时）
3) Payload 必须包含：`stage`（shooting/selecting/stopped）、`isRunning`、`startedAt`、`lastUpdatedAt`（按已有字段/键）
4) 写入 watch 本地状态后触发 UI 更新；必要时写入 watch 的 app group store 供 widget 更新（同设备）。

Acceptance:
- 手表 app 在后台/未打开时：手机端切 stage，之后打开手表 app 看到状态已同步（<=10s 或下一次激活时一致）。
- 手表 app 在前台时：手机端切 stage，1s 内更新（可接受轻微延迟）。
- `xcodebuild` BUILD SUCCEEDED：
  - `PhotoFlowWatch Watch App`（watchOS simulator）
  - `PhotoFlowWatchWidgetExtension`（watchOS simulator）
  - `PhotoFlow`（iphoneos，`CODE_SIGNING_ALLOWED=NO`）
- `docs/AGENTS/exec.md` 记录：payload 格式、发送策略、接收点、手动测试步骤与结果。

StopCondition:
- PR opened to `main`（不合并）
- CI green
- `docs/AGENTS/exec.md` 更新
- STOP
