# Exec Report

- Scope: Fix iOS handling of watch session_event startShooting to keep total ticking.
- Changes:
  - On iOS, startShooting now resets the in-memory session and sets shootingStart before entering Shooting, so total duration starts immediately.
  - Added epoch normalization (ms vs s) before converting watch timestamps to Date.

## Manual Verification
1) From watch, tap “开始拍摄” once.
2) On iPhone, confirm total duration starts ticking immediately (not waiting for end).

## Build
- iOS scheme: PhotoFlow
  - `xcodebuild -project PhotoFlow.xcodeproj -scheme PhotoFlow -destination 'generic/platform=iOS Simulator' build`
- watchOS scheme: PhotoFlowWatch Watch App
  - `xcodebuild -project PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' build`

## TC-WATCH-WIDGET-V0 Placeholder Widget
- Scope: Added a watchOS WidgetKit placeholder implementation (no App Group, no deep link).
- Files:
  - PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift

## Manual Verification
1) Create the watchOS Widget Extension target (steps in PR description) and add `PhotoFlowWatchWidget.swift` to it.
2) Build the watch app + widget extension with `xcodebuild` (commands in PR description).
3) In the watch simulator, add the PhotoFlow complication/Smart Stack widget and confirm it shows placeholder state, elapsed, and last updated time.

## TC-WATCH-WIDGET-V0 Target Wiring
- Changes:
  - Added watchOS Widget Extension target `PhotoFlowWatchWidgetExtension` and embedded it in the watch app.
  - Wired widget extension Info.plist and build phases (sources, frameworks, resources).
  - Added shared scheme for the widget extension so `xcodebuild` can target watchOS Simulator without manual setup.
  - Linked WidgetKit and SwiftUI frameworks for the extension.

## Manual Verification
1) Build and run the watch app in the watch simulator.
2) Long-press the watch face, add a complication or Smart Stack widget.
3) Confirm the PhotoFlow widget shows placeholder state, elapsed time, and last updated time.

## Build
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' build`
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' build`
- Fallback (no signing):
  - `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`

## TC-DEVICE-INSTALL-FIX-WIDGET-APPEX

## Build
- `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*`
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## Embedded AppEx Inspection
- `APP_EX=/Users/zhengxinrong/Library/Developer/Xcode/DerivedData/PhotoFlow-ejgklfquxzampbhawgvwoufqsvze/Build/Products/Debug-iphoneos/PhotoFlow.app/Watch/PhotoFlowWatch Watch App.app/PlugIns/PhotoFlowWatchWidgetExtension.appex`
- `plutil -p "$APP_EX/Info.plist" | egrep 'CFBundleExecutable|CFBundleName|NSExtensionPointIdentifier|NSExtensionPrincipalClass|NSExtensionMainStoryboard'`
  - `"CFBundleExecutable" => "PhotoFlowWatchWidgetExtension"`
  - `"CFBundleName" => "PhotoFlowWatchWidgetExtension"`
  - `"NSExtensionPointIdentifier" => "com.apple.widgetkit-extension"`
- `ls -lah "$APP_EX"`
  - `Info.plist`
  - `PhotoFlowWatchWidgetExtension`
  - `PhotoFlowWatchWidgetExtension.debug.dylib`
  - `__preview.dylib`

## TC-DEVICE-INSTALL-FIX-WIDGET-APPEX (retry)

## Build
- `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*`
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## Embedded AppEx Inspection
- `APP_EX=/Users/zhengxinrong/Library/Developer/Xcode/DerivedData/PhotoFlow-ejgklfquxzampbhawgvwoufqsvze/Build/Products/Debug-iphoneos/PhotoFlow.app/Watch/PhotoFlowWatch Watch App.app/PlugIns/PhotoFlowWatchWidgetExtension.appex`
- `plutil -p "$APP_EX/Info.plist" | egrep 'CFBundleExecutable|CFBundleName|NSExtensionPointIdentifier|NSExtensionPrincipalClass|NSExtensionMainStoryboard'`
  - `"CFBundleExecutable" => "PhotoFlowWatchWidgetExtension"`
  - `"CFBundleName" => "PhotoFlowWatchWidgetExtension"`
  - `"NSExtensionPointIdentifier" => "com.apple.widgetkit-extension"`
- `ls -lah "$APP_EX"`
  - `__preview.dylib`
  - `Info.plist`
  - `PhotoFlowWatchWidgetExtension`
  - `PhotoFlowWatchWidgetExtension.debug.dylib`

## TC-WIDGET-CN-V2A

## Text Updates
- Running -> 拍摄中 (short: 拍摄)
- Stopped -> 已停止 (short: 停止)
- Elapsed -> 用时
- Updated -> 更新 HH:mm (DateFormatter dateFormat = H:mm)

## Build
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **

## TC-WIDGET-CN-V2B

## Store Contract
- App Group: group.com.zhengxinrong.photoflow
- Keys:
  - pf_widget_isRunning (Bool)
  - pf_widget_startedAt (Double, unix ts)
  - pf_widget_lastUpdatedAt (Double, unix ts)
  - pf_widget_stage (String): shooting | selecting | stopped (missing -> stopped)

## Stage Mapping
- shooting -> 拍摄中 (short: 拍摄)
- selecting -> 选片中 (short: 选片)
- stopped/unknown -> 已停止 (short: 停止)
- Updated line: 更新 HH:mm (DateFormatter dateFormat = H:mm)

## Write Points
- startShooting -> stage=shooting (isRunning=true, startedAt=now)
- startSelecting -> stage=selecting (isRunning=true, startedAt=shootingStart)
- end -> stage=stopped (isRunning=false, startedAt=nil)
- restart -> stage=shooting (isRunning=true, startedAt=now)

## Build
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **

## HISTORY: Legacy Deep Link Notes (for audit only)

## TC-DEEPLINK-DL1-ROUTING

## Supported URL Formats
- `photoflow://stage/shooting`
- `photoflow://stage/selecting`
- `photoflow://stage/stopped`
- Any other URL is ignored safely (no crash).

## Routing Behavior (state variables)
- Sets local in-memory state only (no sync / no widget writes):
  - `shooting`: `stage=.shooting`, clears `selectingStart/endedAt`, ensures `shootingStart` exists (missing -> `now`).
  - `selecting`: `stage=.selecting`, clears `endedAt`, ensures `shootingStart/selectingStart` exist (missing -> `now`).
  - `stopped`: `stage=.ended`, sets `endedAt=now` only if `shootingStart` exists (otherwise leaves timestamps empty).

## DEBUG Manual Test Hook
- Watch app (DEBUG builds) shows 3 buttons:
  - `DEBUG: stage/shooting`
  - `DEBUG: stage/selecting`
  - `DEBUG: stage/stopped`
- Tap to simulate `onOpenURL` routing without URL scheme registration (DL-3).

## Build
- `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*`
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## TC-DEEPLINK-DL2-WIDGETURL

## Widget URL Mapping
- shooting -> photoflow://stage/shooting
- selecting -> photoflow://stage/selecting
- stopped -> photoflow://stage/stopped

## Manual Test
1) Change stage in watch app (拍摄/选片/停止).
2) Tap the widget; confirm the app receives photoflow://stage/<stage>.

## Build
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
  - Result: ** BUILD SUCCEEDED **

## TC-SYNC-PHONE-TO-WATCH-V1

## Payload Schema
- stage (String): shooting | selecting | stopped
- isRunning (Bool)
- startedAt (Double, unix ts) optional
- lastUpdatedAt (Double, unix ts)

## Send / Receive Points
- iPhone send: `PhotoFlow/PhotoFlow/ContentView.swift` -> `WatchSyncStore.sendStageSync(...)` called after stage changes and reset.
- Watch receive: `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift` -> `session(_:didReceiveApplicationContext:)` + `session(_:didReceiveMessage:)` -> `applyStatePayload(...)`.
- Watch apply: `ContentView.applyIncomingState(...)` updates stage/session and writes widget defaults.

## Build
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## Manual Test
- PASS:
  - PASS: watch 关闭后再打开能同步
  - PASS: watch 前台时 ~1s 内更新

## TC-SYNC-PHONE-TO-WATCH-V2-CONSISTENCY

## Ordering Rule
- Ordering key: lastUpdatedAt (Double, unix ts) reused from V1 payload.
- Watch stores last applied timestamp in UserDefaults key `pf_sync_lastAppliedAt`.
- Incoming state is ignored if lastUpdatedAt <= lastApplied; payloads missing lastUpdatedAt are ignored once lastApplied exists.

## Apply Latest Context
- Watch reads `receivedApplicationContext` (fallback to `applicationContext`) after WCSession activation and on app start if already activated, then applies state payload.

## Build
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **

## Manual Test
- PASS: Test A (watch app closed → iPhone changes stage 5 times → wait 10s → open watch app → last stage shown).
- PASS: Test B (watch app foreground → iPhone change stage → watch updates within ~1s).
- PASS: Test C (disconnect/reconnect → open watch app → last stage shown).

## TC-SYNC-DIAG-DASHBOARD

## How To Open
- iPhone: tap the small Debug button at the bottom of the main screen (DEBUG builds only).
- Watch: tap the small Debug button under the DEBUG stage buttons (DEBUG builds only).

## Fields
- lastSentPayload (iPhone): last payload sent to watch (key=value list).
- lastReceivedPayload (watch): most recent payload received from phone.
- lastAppliedAt (watch): last applied lastUpdatedAt timestamp (epoch + H:mm:ss).
- sessionStatus: activation/reachable/pairing/installed flags for WCSession.

## Build
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **

## Manual Test
- PASS: iPhone change stage → watch dashboard updates.

## TC-COMPLICATION-TAP-OPEN-APP

## Widget Tap Behavior
- Removed widgetURL/link to use system default open behavior.
- Supported families: accessoryCircular, accessoryRectangular, accessoryCorner.

## Build
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## Manual Test
- PASS: Add circular/corner/rectangular complications and tap each → PhotoFlow Watch App opens (default entry), no crash.

## TC-CLEANUP-DEEPLINK-RESIDUALS

## Removed
- Watch app: onOpenURL + deep link parsing helpers.
- Watch app: DEBUG stage deep link buttons.
- Widget: no widgetURL/link usage (already removed in prior PR).

## Repo Check
- `rg "photoflow://|handleDeepLink|onOpenURL|DEBUG: stage" -n`
  - Output:
    - docs/AGENTS/exec.md:134:- `photoflow://stage/shooting`
    - docs/AGENTS/exec.md:135:- `photoflow://stage/selecting`
    - docs/AGENTS/exec.md:136:- `photoflow://stage/stopped`
    - docs/AGENTS/exec.md:147:  - `DEBUG: stage/shooting`
    - docs/AGENTS/exec.md:148:  - `DEBUG: stage/selecting`
    - docs/AGENTS/exec.md:149:  - `DEBUG: stage/stopped`
    - docs/AGENTS/exec.md:150:- Tap to simulate `onOpenURL` routing without URL scheme registration (DL-3).
    - docs/AGENTS/exec.md:164:- shooting -> photoflow://stage/shooting
    - docs/AGENTS/exec.md:165:- selecting -> photoflow://stage/selecting
    - docs/AGENTS/exec.md:166:- stopped -> photoflow://stage/stopped
    - docs/AGENTS/exec.md:170:2) Tap the widget; confirm the app receives photoflow://stage/<stage>.
    - docs/AGENTS/queue.md:31:Title: 清理深链残留（photoflow/onOpenURL/DEBUG deep link），避免未来误触
    - docs/AGENTS/queue.md:35:- 移除所有深链相关残留：`photoflow://`、`onOpenURL`/`handleDeepLink`、`DEBUG` stage 深链测试入口
    - docs/AGENTS/queue.md:51:  - `photoflow://`、`handleDeepLink`、`onOpenURL`、`DEBUG: stage`
  - Notes: matches are limited to exec.md history and the queue task card (queue.md is not edited).

## Build
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## Manual Test
- FAIL: Open watch app from app list (no crash). Not run; needs device/simulator UI.
- FAIL: Tap complication opens app (default entry). Not run; needs device/simulator UI.

## TC-WATCH-DEBUG-UI-CLEANUP

## Manual Verification
1) Watch home screen (DEBUG build): no debug entry visible by default. (PASS)
2) Tap the title area 5 times to toggle the debug panel; confirm the debug UI appears. (PASS)

## Build
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **

## TC-WATCH-STATUS-BANNER-V1

## Manual Verification
1) 断连/连上时状态条从“未连接/已连接”变化。 (NOT RUN)
2) 同步发生时“最近同步”时间更新。 (NOT RUN)
3) stage 切换有 haptic。 (NOT RUN)

## Build
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - Result: ** BUILD SUCCEEDED **
