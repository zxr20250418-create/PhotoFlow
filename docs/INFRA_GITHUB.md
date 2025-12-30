We pin required checks with `gh api` to avoid UI drift and to keep branch protection reproducible across machines. This makes the gate auditable and guarantees the same required context string for CI.

Standard flow: create `work/*`, open PR, merge only after CI passes; if CI needs a rerun, use `bash scripts/retrigger_ci.sh` which triggers workflow_dispatch and falls back to an empty commit push when needed. Keep changes small and scoped so main stays releasable.

Evidence pack commands (run as needed):
git log --oneline -n 5
git status -sb
gh run list -L 5
gh api repos/OWNER/REPO/branches/main/protection/required_status_checks -q '.contexts'
bash scripts/check_versions.sh
