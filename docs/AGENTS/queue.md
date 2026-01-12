## DONE — TC-WIDGET-CN-V2B

ID: TC-WIDGET-CN-V2B
Status: DONE (merged)

## ACTIVE — TC-DEEPLINK-DL2-WIDGETURL

ID: TC-DEEPLINK-DL2-WIDGETURL
Title: Widget URL wiring (DL-2, Swift-only)
AssignedTo: Executor
Goal: Set `widgetURL` based on stage: `photoflow://stage/shooting|selecting|stopped`; no `Info.plist`/`pbxproj` changes.
Scope: Allowed files ONLY: `PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift` and `docs/AGENTS/exec.md`.
Forbidden: No `Info.plist` / `project.pbxproj` changes.
Acceptance: `xcodebuild` watch app + widget extension + `iphoneos` build all show `BUILD SUCCEEDED` (`CODE_SIGNING_ALLOWED=NO` ok).
StopCondition: PR opened (no merge), CI green, `docs/AGENTS/exec.md` updated, STOP.
