#!/usr/bin/env bash
set -euo pipefail

PR_NUM="${1:-}"
OUT="${2:-}"

mkdir -p artifacts

{
  echo "== Evidence"
  echo "Time: $(date -Iseconds)"
  echo "Repo: $(pwd)"
  echo
  echo "== Git status"
  git status -sb || true
  echo
  echo "== Recent commits"
  git log --oneline -n 20 || true
  echo
  echo "== verify.md (first 200 lines)"
  sed -n '1,200p' docs/AGENTS/verify.md 2>/dev/null || echo "(missing docs/AGENTS/verify.md)"
  echo
  if [[ -n "$PR_NUM" ]]; then
    echo "== PR #$PR_NUM checks"
    gh pr checks "$PR_NUM" || true
  fi
} | tee "$OUT" >/dev/null
