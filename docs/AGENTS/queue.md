# Task Queue
#
# NOTE: Keep exactly one ACTIVE task card.

## DONE/ARCHIVED — TC-RG-HARDGATE

ID: TC-RG-HARDGATE
Status: DONE/ARCHIVED

## ACTIVE — TC-IOS-BUILD-FIX-WCSESSION

ID: TC-IOS-BUILD-FIX-WCSESSION
Title: Fix iphoneos build failure (WCSessionDelegate conformance)
AssignedTo: Executor
Goal: `xcodebuild -scheme "PhotoFlow" -sdk iphoneos` succeeds (`CODE_SIGNING_ALLOWED=NO`).
Scope: Swift-only edits; allowed files: `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift`, `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift` ONLY.
Forbidden: Do NOT modify `project.pbxproj`, `Info.plist`, entitlements, or any other files.
Acceptance: Run `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*` then `xcodebuild build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO` returns `BUILD SUCCEEDED`.
StopCondition: `iphoneos` `xcodebuild` shows `BUILD SUCCEEDED` + embedded `.appex` check output is recorded + PR opened to `main` (no merge); STOP.
