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

## ACTIVE — TC-SYNC-PHONE-TO-WATCH-V2-CONSISTENCY
ID: TC-SYNC-PHONE-TO-WATCH-V2-CONSISTENCY
Title: 断连/后台最终一致性（updateApplicationContext）V2
AssignedTo: Executor

Goal:
- Watch 长时间没开/不在前台时，iPhone 多次切换 stage，Watch 下次打开必须显示“最后一次状态”（最终一致）。
- 前台仍保持 1s 内更新（V1 fast path 不回退）。

Scope (Allowed files ONLY):
- `PhotoFlow/PhotoFlow/ContentView.swift`（iPhone 侧同步发送处）
- `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`（watch 侧接收/应用处）
- `docs/AGENTS/exec.md`（追加）

Forbidden:
- 禁止修改 `Info.plist` / `project.pbxproj` / entitlements / targets / build settings
- 不新增文件/不重构架构

Implementation requirements:
1) Payload 增加“去乱序”字段（不破坏兼容）：
   - `pf_sync_seq` (Int) 或 `pf_sync_lastUpdatedAt` (Double unix ts) 作为版本号
   - Watch 端只应用“更新更晚/seq 更大”的 payload，旧的忽略
2) Watch 端在启动/激活时主动拉取最新 applicationContext：
   - 在 WCSession 激活完成后读取 `session.receivedApplicationContext` / `applicationContext` 并 apply（确保最终一致）
3) `applyIncomingState` 必须在主线程/MainActor
4) 将 lastApplied seq/ts 持久化到本地 UserDefaults（watch 本机即可），防止重复回滚

Acceptance:
- 手动测试通过（记录在 `docs/AGENTS/exec.md`）：
  A) watch app 完全关闭：iPhone 连续切换 stage 5 次（shooting/selecting/stopped…），等待 10s，打开 watch app -> 显示最后一次 stage
  B) watch app 前台：iPhone 切换 stage -> 1s 内更新
  C) iPhone 与 watch 临时断连（例如关 watch 蓝牙/飞行模式再恢复）：恢复后打开 watch -> 仍是最后状态
- `xcodebuild` BUILD SUCCEEDED（`CODE_SIGNING_ALLOWED=NO` 可）：
  - `PhotoFlowWatch Watch App`
  - `PhotoFlowWatchWidgetExtension`
  - `PhotoFlow`（iphoneos）

StopCondition:
- PR opened to `main`（不合并）
- CI green
- `docs/AGENTS/exec.md` 追加：payload 字段、去乱序逻辑、测试步骤与结果
- STOP
