# PhotoFlow Spec

## Targets
- iOS App: PhotoFlow
- watchOS: yes
  - If yes: Watch App target(s) are created by Xcode’s “Watch App for iOS App” template.

## v0 (HISTORICAL, not current)
- v0 watch excluded complication/widgetkit to reduce scope and target wiring risk during initial watch setup.
- Time window: Dec 2025–Jan 2026 (initial watch target bring-up).

## v1 (CURRENT)
- Scope includes: watch app, widget/complication, phone↔watch sync (V1/V2), diagnostics/status banner, complication tap-to-open app.
- Guardrails: iOS-only workflow uses `bash scripts/ios_safe.sh --clean-deriveddata`.
- High-risk changes (Info.plist/pbxproj/entitlements) only via “config cards” with strict preflight outputs required.

### Gates (config cards)
- exec.md must include: `preflight_build.sh` / `ios_safe.sh` output.
- exec.md must include: embedded widget appex check.
- exec.md must include: embedded watch app/watchkit extension check.

## Bundle Identifiers
- iOS: com.zhengxinrong.PhotoFlow
- watchOS (if any): derived from iOS bundle id by Xcode; keep consistent and documented after creation.

## Minimum Deployment
- iOS: 17.0
- watchOS (if any): 10.0

## Versioning Rules (Hard)
- MARKETING_VERSION starts at `0.1.0`
- CURRENT_PROJECT_VERSION (Build) starts at `1`
- **All targets must always share the same MARKETING_VERSION and Build**

## Local Build
- iOS build:
  - `bash scripts/check_versions.sh`
  - `bash scripts/build_ios.sh`
- watch build (if enabled):
  - `bash scripts/build_watch.sh`

## Release (TestFlight)
- Bump Build:
  - `bash scripts/bump_build.sh`
  - commit: `chore(build): bump build`
- Verify:
  - `bash scripts/check_versions.sh`
  - `bash scripts/build_ios.sh` (+ watch if enabled)
- Archive & Upload via Xcode Organizer (or xcodebuild archive later, if introduced)
- Tag after successful upload:
  - `git tag -a v${MARKETING_VERSION}+${BUILD} -m "Release v${MARKETING_VERSION}+${BUILD}"`
  - `git push --tags`
