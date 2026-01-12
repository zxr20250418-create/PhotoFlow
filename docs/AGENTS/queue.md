## DONE — TC-WIDGET-CN-V2B

ID: TC-WIDGET-CN-V2B
Status: DONE (merged)

## ACTIVE — TC-DEEPLINK-DL1-ROUTING

ID: TC-DEEPLINK-DL1-ROUTING
Title: Deep link routing (DL-1, Swift-only)
AssignedTo: Executor
Goal: Add `onOpenURL` handling and route parsing for URLs like `photoflow://stage/<shooting|selecting|stopped>`; no `Info.plist`/`pbxproj` changes.
Scope: Allowed files ONLY: `PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift` (or watch app entry/root) and `docs/AGENTS/exec.md`.
Forbidden: No `Info.plist` / `project.pbxproj` changes.
Acceptance: `xcodebuild` watch app + widget extension + `iphoneos` build all show `BUILD SUCCEEDED` (`CODE_SIGNING_ALLOWED=NO` ok).
StopCondition: PR opened (no merge), CI green, `docs/AGENTS/exec.md` updated, STOP.
