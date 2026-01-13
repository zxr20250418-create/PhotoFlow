#!/usr/bin/env bash
set -euo pipefail

clean=0
for arg in "$@"; do
  case "$arg" in
    --clean-deriveddata)
      clean=1
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      echo "Usage: $0 [--clean-deriveddata]" >&2
      exit 2
      ;;
  esac
 done

if [ "$clean" -eq 1 ]; then
  echo "Cleaning DerivedData..."
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData/PhotoFlow-"*
fi

echo "+ xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme \"PhotoFlow\" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build"
xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlow" -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build

echo "+ xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme \"PhotoFlowWatch Watch App\" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build"
xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build

echo "+ xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme \"PhotoFlowWatchWidgetExtension\" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build"
xcodebuild -project PhotoFlow/PhotoFlow.xcodeproj -scheme "PhotoFlowWatchWidgetExtension" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
