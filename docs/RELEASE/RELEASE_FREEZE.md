# Release Freeze 2026-01-18

Baseline
- Tag: appstore-upload-2026-01-18-53641b4
- Release branch: release/2026-01-18-appstore-53641b4

Allowed during freeze
- Swift-only fixes (iPhone/watch) that do not touch build configuration
- App Store metadata updates (screenshots, copy, etc.)

Not allowed during freeze
- project.pbxproj / Info.plist / entitlements / targets / appex
- Watch/Widget configuration changes

Process rule
- Any required configuration changes must go through a dedicated config PR and be reviewed separately.
