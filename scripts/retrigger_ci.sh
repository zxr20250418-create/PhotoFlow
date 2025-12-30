#!/usr/bin/env bash
set -euo pipefail

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "ERROR: cannot determine current branch"
  exit 1
fi

if [[ "$branch" == "main" ]]; then
  echo "ERROR: refuse to run on main"
  exit 1
fi

if command -v gh >/dev/null 2>&1; then
  if gh workflow run .github/workflows/ci.yml --ref "$branch"; then
    echo "OK: triggered CI on $branch"
    exit 0
  fi
  echo "WARN: gh workflow run failed, falling back"
else
  echo "WARN: gh not found, falling back"
fi

git commit --allow-empty -m "chore: retrigger CI"
git push
