#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "ERROR: working tree is dirty; commit or stash changes before closeout." >&2
  exit 1
fi

git switch main

git pull --ff-only

if [[ "$#" -gt 0 ]]; then
  for branch in "$@"; do
    [[ -z "$branch" ]] && continue
    git push origin --delete "$branch" >/dev/null 2>&1 || echo "WARN: remote branch not deleted: $branch"
    git branch -D "$branch" >/dev/null 2>&1 || echo "WARN: local branch not deleted: $branch"
  done
fi

git fetch -p

bash scripts/protect_main.sh

echo "OK closeout completed."
