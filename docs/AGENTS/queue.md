## ACTIVE — TC-IOS-BUILD-FIX-WIDGETKIT
ID: TC-IOS-BUILD-FIX-WIDGETKIT
Title: Fix iphoneos build so device install stops “install then disappear”
AssignedTo: Executor

Allowed files (ONLY):
- PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift
- PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift

Goal:
- xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO
  returns BUILD SUCCEEDED

Scope:
- Add iOS-only WCSessionDelegate methods wrapped in #if os(iOS) (no override)
- Guard all .accessoryCorner usage so iphoneos build never compiles watch-only symbols:
  - #Preview(accessoryCorner) under #if os(watchOS)
  - .supportedFamilies includes .accessoryCorner only on watchOS

Forbidden:
- No project.pbxproj / Info.plist / entitlements changes
- No other files

StopCondition:
- BUILD SUCCEEDED
- Embedded appex inspection output shows:
  - NSExtensionPointIdentifier == com.apple.widgetkit-extension
  - CFBundleExecutable + CFBundleName present and non-empty
  - NSExtensionPrincipalClass absent
  - NSExtensionMainStoryboard absent
- PR opened to main (no merge)
- docs/AGENTS/exec.md updated with commands + outputs
- STOP
