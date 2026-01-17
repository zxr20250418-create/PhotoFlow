#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
clean_arg=""
allow_watch_swift="${ALLOW_WATCH_SWIFT:-0}"
for arg in "$@"; do
  case "$arg" in
    --clean-deriveddata)
      clean_arg="--clean-deriveddata"
      ;;
    --allow-watch-swift)
      allow_watch_swift="1"
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      echo "Usage: $0 [--clean-deriveddata] [--allow-watch-swift]" >&2
      exit 2
      ;;
  esac
done

if [ "$allow_watch_swift" = "1" ]; then
  export ALLOW_WATCH_SWIFT=1
fi

"$script_dir/guard_ios_only.sh"
"$script_dir/preflight_build.sh" $clean_arg

echo "PASS: iOS-only guardrails and builds succeeded."
