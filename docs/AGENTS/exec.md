# Exec Report

- Scope: Fix live timer refresh for iOS + watch ContentView.
- Changes:
  - Wrapped the stage/title + duration display in `TimelineView(.periodic(from: .now, by: 1))` to tick every second.
  - Recomputed total duration as `(endedAt ?? now) - shootingStart` and current stage as `now - stageStart` so numbers update immediately after entering Shooting.

## Manual Verification
1) iOS: tap “上班” then “开始拍摄” and confirm total/current stage timers start ticking within 1s.
2) watchOS: trigger “开始拍摄” and confirm total/current stage timers tick immediately.

## Build
- iOS scheme: PhotoFlow
  - `xcodebuild -project PhotoFlow.xcodeproj -scheme PhotoFlow -destination 'generic/platform=iOS Simulator' build`
- watchOS scheme: PhotoFlowWatch Watch App
  - `xcodebuild -project PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' build`
