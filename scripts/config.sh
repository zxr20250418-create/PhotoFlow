#!/usr/bin/env bash
set -euo pipefail
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
XCODEPROJ="${XCODEPROJ:-PhotoFlow/PhotoFlow.xcodeproj}"
IOS_SCHEME="${IOS_SCHEME:-PhotoFlow}"
WATCH_SCHEME="${WATCH_SCHEME:-PhotoFlowWatch Watch App}"
