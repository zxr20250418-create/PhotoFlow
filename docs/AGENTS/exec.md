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

## TC-DEEPLINK-DL3-SCHEME

## Watch URL Scheme
- Watch app registers URL scheme: `photoflow`
- Key: `CFBundleURLTypes` (in watch app built `Info.plist`)

## Project Wiring
- Watch app target uses explicit Info.plist:
  - `INFOPLIST_FILE = "PhotoFlowWatch Watch App/PhotoFlowWatchAppInfo.plist"`
  - `GENERATE_INFOPLIST_FILE = NO`
- Widget extension `Info.plist` unchanged.

## Build (clean)
- `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*`
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **
- `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: ** BUILD SUCCEEDED **

## Embedded AppEx Inspection (Debug-iphoneos)
- `APP_EX=~/Library/Developer/Xcode/DerivedData/PhotoFlow-*/Build/Products/Debug-iphoneos/PhotoFlow.app/Watch/PhotoFlowWatch\\ Watch\\ App.app/PlugIns/PhotoFlowWatchWidgetExtension.appex`
- `plutil -p "$APP_EX/Info.plist" | egrep 'CFBundleExecutable|CFBundleName|NSExtensionPointIdentifier|NSExtensionPrincipalClass|NSExtensionMainStoryboard'`
  - `"CFBundleExecutable" => "PhotoFlowWatchWidgetExtension"`
  - `"CFBundleName" => "PhotoFlowWatchWidgetExtension"`
  - `"NSExtensionPointIdentifier" => "com.apple.widgetkit-extension"`
  - (no `NSExtensionPrincipalClass` / `NSExtensionMainStoryboard`)

## Watch App Info.plist Check (Debug-watchsimulator)
- `WATCH_APP_PLIST=~/Library/Developer/Xcode/DerivedData/PhotoFlow-*/Build/Products/Debug-watchsimulator/PhotoFlowWatch\\ Watch\\ App.app/Info.plist`
- `plutil -p "$WATCH_APP_PLIST" | egrep 'CFBundleURLTypes|photoflow'`
  - `"CFBundleURLTypes" => [...]`
  - `photoflow`

## Manual Smoke (required, needs signed Run)
- Xcode Run `PhotoFlow` to a physical iPhone (Debug):
  - App installs and does **not** “install then disappear”.
- On Watch: add the widget/complication, tap it:
  - Opens watch app via `photoflow://stage/<shooting|selecting|stopped>`
  - DL-1 routing lands on the expected stage screen.

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

## TC-DEEPLINK-DL3-WATCH-PLIST

## Watch App Info.plist Keys Added
- WKWatchKitApp = YES
- WKApplication = YES

## Embedded Watch App Info.plist Check
- `plutil -p "$WATCH_PLIST" | egrep 'WKWatchKitApp|WKApplication|CFBundleURLTypes'`
  - "CFBundleURLTypes" => [
  - "WKApplication" => 1
  - "WKWatchKitApp" => 1

## devicectl Install
- `xcrun devicectl device uninstall app --device 202 com.zhengxinrong.PhotoFlow --quiet || true`
- `xcrun devicectl device install app --device 202 "$APP_PATH"`
  - ERROR: com.zhengxinrong.PhotoFlow.watchkitapp: Missing WKCompanionAppBundleIdentifier key in WatchKit 2.0 app's Info.plist
