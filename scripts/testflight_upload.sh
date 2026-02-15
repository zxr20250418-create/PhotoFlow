#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 1) Auto bump build number
bash scripts/bump_build.sh

# 2) Archive
mkdir -p build
xcodebuild \
  -project "PhotoFlow/PhotoFlow.xcodeproj" \
  -scheme "PhotoFlow" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "build/PhotoFlow.xcarchive" \
  clean archive \
  -allowProvisioningUpdates

# 3) Upload to TestFlight (App Store Connect)
cat > build/ExportOptions-upload.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>KXMLG2TV28</string>
  <key>destination</key>
  <string>upload</string>
  <key>uploadSymbols</key>
  <true/>
  <key>uploadBitcode</key>
  <false/>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "build/PhotoFlow.xcarchive" \
  -exportOptionsPlist "build/ExportOptions-upload.plist" \
  -exportPath "build/upload" \
  -allowProvisioningUpdates

echo "Done: uploaded to TestFlight."
