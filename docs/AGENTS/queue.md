## ACTIVE — TC-DEVICE-INSTALL-FIX-WIDGET-APPEX

ID: TC-DEVICE-INSTALL-FIX-WIDGET-APPEX
Title: Fix “install then disappear” by making embedded widget appex metadata valid for WidgetKit
AssignedTo: Executor

Allowed files (ONLY):
- PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift
- PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift
- PhotoFlow/PhotoFlowWatchWidget/Info.plist
- PhotoFlow/PhotoFlow.xcodeproj/project.pbxproj (ONLY if needed to ensure the widget extension target uses the correct Info.plist / disable generated Info.plist injection)

Goal:
- Device install no longer rolls back (“install then disappear”).
- Embedded appex passes metadata rules for WidgetKit.

Scope:
1) Keep PR #24 fixes (iphoneos build must remain BUILD SUCCEEDED).
2) Fix embedded appex Info.plist so that for extension point `com.apple.widgetkit-extension`:
   - `NSExtensionPrincipalClass` must be ABSENT
   - `NSExtensionMainStoryboard` must be ABSENT
   - `CFBundleExecutable` present & non-empty, and the executable file exists inside the `.appex`
   - `CFBundleName` present & non-empty
   - `NSExtensionPointIdentifier == com.apple.widgetkit-extension`
3) If those forbidden keys keep reappearing, allow minimal pbxproj/build-settings change to:
   - force `INFOPLIST_FILE` to `PhotoFlow/PhotoFlowWatchWidget/Info.plist` for the widget target (all configs)
   - disable `GENERATE_INFOPLIST_FILE` for the widget target
   - remove any `INFOPLIST_KEY_NSExtensionPrincipalClass` / storyboard injection

Acceptance:
- `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*` then
  `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO`
  => `BUILD SUCCEEDED`
- Embedded appex inspection (Debug-iphoneos) shows:
  - `CFBundleExecutable` / `CFBundleName` present
  - `NSExtensionPrincipalClass` absent
  - `NSExtensionMainStoryboard` absent
  - `NSExtensionPointIdentifier` correct
- Running on device succeeds (no install rollback).
- Update `docs/AGENTS/exec.md` with the commands + inspection output.

StopCondition:
- Update PR #24 (preferred) or open a new PR, CI green, `docs/AGENTS/exec.md` updated; STOP.
