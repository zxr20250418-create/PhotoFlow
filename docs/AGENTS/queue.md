## ACTIVE — TC-PREFLIGHT-EMBEDDED-WATCHAPP
ID: TC-PREFLIGHT-EMBEDDED-WATCHAPP
Title: Add embedded Watch App + Widget appex preflight checks (prevent install regressions)
AssignedTo: Executor

Goal:
- Any PR touching `Info.plist` / `project.pbxproj` / targets/embedding must pass preflight locally before merge.
- Preflight must catch:
  1) Watch app plist errors (e.g. `WKApplication`/`WKWatchKitApp` conflicts, `UIDeviceFamily` missing `4`, missing `WKCompanionAppBundleIdentifier`)
  2) WatchKit extension not embedded (ValidateEmbeddedBinary-class failures)
  3) WidgetKit appex metadata invalid (existing script)

AllowedFiles:
- scripts/check_embedded_watch_app.sh (new)
- scripts/preflight_device_install.sh (new, optional wrapper)
- docs/AGENTS/exec.md (append usage)
- docs/AGENTS/queue.md (this card)
- .gitignore (only if needed)

Forbidden:
- Do NOT modify any Swift.
- Do NOT modify `project.pbxproj` / any `Info.plist` in this task.

Acceptance:
1) After building Debug-iphoneos `PhotoFlow` (CODE_SIGNING_ALLOWED=NO ok), preflight verifies:
   A) Embedded watch app `Info.plist`:
      - `WKWatchKitApp == true`
      - `WKApplication` ABSENT (must not exist)
      - `WKCompanionAppBundleIdentifier` non-empty
      - `UIDeviceFamily` includes `4`
      - `CFBundleURLTypes` contains scheme `photoflow` (if DL-3 enabled)
   B) Embedded watch app `PlugIns` contains WatchKit extension `.appex` (NOT just widget `.appex`)
      - Its `Info.plist` has `NSExtensionPointIdentifier == com.apple.watchkit`
   C) Embedded widget `.appex` passes `scripts/check_embedded_widget_appex.sh` (existing)
2) `docs/AGENTS/exec.md` documents how to run preflight + PASS/FAIL meaning.
3) Open PR to main (no merge) and STOP.

PolicyUpdate:
- Any future PR that touches `Info.plist` / `project.pbxproj` MUST paste preflight output into `docs/AGENTS/exec.md` before Coordinator merges.
