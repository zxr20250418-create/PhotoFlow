#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LOCAL_BUILD="${LOCAL_BUILD:-true}"
EVIDENCE="${EVIDENCE:-true}"
PR_TITLE="${PR_TITLE:-}"
DELETE_LOCAL_BRANCH="${DELETE_LOCAL_BRANCH:-true}"
BYPASS_RG="${BYPASS_RG:-false}"

die() { echo "ERROR: $*" >&2; exit 1; }

gh auth status >/dev/null

cur="$(git branch --show-current)"
if [[ "$cur" == "$DEFAULT_BRANCH" ]]; then
  cur="work/ship-$(date +%m%d%H%M%S)"
  git switch -c "$cur"
fi

LOCAL_BUILD="$LOCAL_BUILD" bash scripts/auto_gate.sh
grep -q "AUTO_GATE=PASS" docs/AGENTS/verify_auto.md || die "AUTO_GATE not PASS"
if [[ "$BYPASS_RG" != "true" ]]; then
  grep -q "RG-V1: PASS" docs/AGENTS/verify.md || die "RG-V1 not PASS"
else
  echo "==> BYPASS_RG=true (skip RG-V1 gate)"
fi

git add scripts/*.sh docs/AGENTS/verify.md docs/AGENTS/verify_auto.md 2>/dev/null || true
extra_paths=""
while IFS= read -r path; do
  case "$path" in
    scripts/*.sh|docs/AGENTS/verify.md|docs/AGENTS/verify_auto.md) ;;
    "") ;;
    *) extra_paths+="${path}"$'\n' ;;
  esac
done < <(git diff --name-only --cached)
if [[ -n "$extra_paths" ]]; then
  echo "ERROR: ship_2stage allowlist violation. Unapproved files staged:" >&2
  echo "$extra_paths" >&2
  echo "Allowed: scripts/*.sh, docs/AGENTS/verify.md, docs/AGENTS/verify_auto.md" >&2
  exit 1
fi
if [[ -n "$(git diff --cached --name-only)" ]]; then
  git commit -m "chore: ship (auto gate pass)"
fi

git push -u origin HEAD >/dev/null

pr_num=""
if gh pr view --json number -q .number >/dev/null 2>&1; then
  pr_num="$(gh pr view --json number -q .number)"
else
  if [[ -n "$PR_TITLE" ]]; then
    gh pr create --title "$PR_TITLE" --body "" --base "$DEFAULT_BRANCH" >/dev/null
  else
    gh pr create --fill --base "$DEFAULT_BRANCH" >/dev/null
  fi
  pr_num="$(gh pr view --json number -q .number)"
fi

echo "==> PR #$pr_num for branch $cur"

gh pr checks "$pr_num" --watch
gh pr merge "$pr_num" --merge --delete-branch

git switch "$DEFAULT_BRANCH"
git pull --ff-only

if [[ "$EVIDENCE" == "true" ]]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  out="artifacts/evidence_${ts}.txt"
  bash scripts/evidence_pack.sh "$pr_num" "$out"
  echo "==> Evidence saved: $out"
fi

if [[ "$DELETE_LOCAL_BRANCH" == "true" ]]; then
  if git show-ref --verify --quiet "refs/heads/$cur"; then
    git branch -D "$cur" >/dev/null 2>&1 || true
  fi
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "WARNING: working tree not clean:"
  git status -sb
  echo "Tip: commit remaining changes, or delete/ignore untracked files (e.g., docs/SESSIONS, artifacts)."
else
  echo "==> Clean: working tree is clean."
fi

echo "==> Done."
