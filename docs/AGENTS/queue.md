## ACTIVE — TC-DL3-WATCHKIT-EMBED-FIX
ID: TC-DL3-WATCHKIT-EMBED-FIX
Title: Fix embedded WatchKit Extension missing in Debug-iphoneos
AssignedTo: Executor

AllowedFiles:
- PhotoFlow/PhotoFlow.xcodeproj/project.pbxproj
- PhotoFlow/PhotoFlowWatch Watch App/PhotoFlowWatchExtensionInfo.plist (may add + commit)
- docs/AGENTS/exec.md

Forbidden:
- Do NOT modify any Swift
- Do NOT modify widget extension Info.plist
- Do NOT modify entitlements (unless install explicitly reports signing/entitlements; this card does not cover it)
- Do NOT commit xcuserdata

Goal:
- `xcodebuild clean build -scheme "PhotoFlow"` (signed) no longer fails at `ValidateEmbeddedBinary`
- Debug-iphoneos embedded Watch App contains WatchKit Extension `.appex`

Acceptance:
A) Signed build succeeds (no forced -sdk):
- `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoFlow-*`
- `xcodebuild clean build -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -configuration Debug -destination 'id=00008120-00064CDE34E8C01E' -allowProvisioningUpdates`
- Result: `BUILD SUCCEEDED` and no `ValidateEmbeddedBinary` error

B) Debug-iphoneos artifact evidence:
- `IOS_APP=~/Library/Developer/Xcode/DerivedData/PhotoFlow-*/Build/Products/Debug-iphoneos/PhotoFlow.app`
- `WATCH_APP="$IOS_APP/Watch/PhotoFlowWatch Watch App.app"`
- `ls -la "$WATCH_APP/PlugIns"` shows BOTH:
  - `PhotoFlowWatch Watch Extension.appex` (WatchKit extension)
  - `PhotoFlowWatchWidgetExtension.appex` (WidgetKit extension)
- `plutil -p "$WATCH_APP/PlugIns/PhotoFlowWatch Watch Extension.appex/Info.plist" | grep NSExtensionPointIdentifier`
  - Must be `com.apple.watchkit`

StopCondition:
- Executor updates existing PR (or opens new PR), CI green, `docs/AGENTS/exec.md` includes the evidence outputs above; STOP
- Coordinator re-runs the signed build command above to confirm pass before merging feature PRs
