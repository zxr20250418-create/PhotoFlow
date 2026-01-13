#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
clean_arg=""
for arg in "$@"; do
  case "$arg" in
    --clean-deriveddata)
      clean_arg="--clean-deriveddata"
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      echo "Usage: $0 [--clean-deriveddata]" >&2
      exit 2
      ;;
  esac
done

"$script_dir/guard_ios_only.sh"
"$script_dir/preflight_build.sh" $clean_arg

echo "PASS: iOS-only guardrails and builds succeeded."
