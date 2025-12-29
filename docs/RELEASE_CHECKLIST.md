# Release Checklist (TestFlight)

## Before you bump
- Working tree clean: `git status`
- On correct branch: `git branch --show-current`

## Version/Build
- `bash scripts/check_versions.sh` must pass
- `bash scripts/bump_build.sh`
- Commit: `chore(build): bump build`

## Build verification
- `bash scripts/check_versions.sh`
- `bash scripts/build_ios.sh`
- If WITH_WATCH=yes: `bash scripts/build_watch.sh`

## Archive & Upload
- Xcode > Product > Archive
- Organizer > Distribute App > TestFlight (App Store Connect)
- Confirm processing success in App Store Connect
- Install from TestFlight on device(s), smoke test

## Tag
- `git tag -a v<MARKETING_VERSION>+<BUILD> -m "Release ..."`
- `git push --tags`
