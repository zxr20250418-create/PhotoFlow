# PhotoFlow Spec

## Targets
- iOS App: PhotoFlow
- watchOS: yes
  - If yes: Watch App target(s) are created by Xcode’s “Watch App for iOS App” template, **v0 must NOT include Complication/WidgetKit**.

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
