#!/usr/bin/env bash
set -euo pipefail

PROJECT="$(find . -maxdepth 2 -name "*.xcodeproj" -print -quit || true)"
if [[ -z "${PROJECT}" ]]; then
  echo "ERROR: No .xcodeproj found. Create the Xcode project first (Step B), then re-run."
  exit 1
fi

if ! command -v agvtool >/dev/null 2>&1; then
  echo "ERROR: agvtool not found. Install Xcode Command Line Tools / Xcode."
  exit 1
fi

echo "Bumping build number for all targets..."
agvtool next-version -all

echo "Now commit it:"
echo "  git add ."
echo "  git commit -m \"chore(build): bump build\""
