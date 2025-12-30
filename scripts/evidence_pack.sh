#!/usr/bin/env bash
set -euo pipefail

pwd

date -u

echo "branch: $(git branch --show-current)"
echo "head: $(git rev-parse HEAD)"

git status -sb

git log -n 5

ls -la docs scripts .github/workflows | sed -n '1,200p'
