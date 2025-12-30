# CODEX_PLAYBOOK.md

## Prompt 1: Start of work (read handoff + evidence)
Read `docs/HANDOFF_CODEX.md` and `docs/HANDOFF_CHATGPT.md` first, then run:
- pwd
- git status -sb
- git log --oneline -n 10
- bash scripts/evidence_pack.sh | sed -n '1,60p'
Then propose one minimal, verifiable goal and the exact commands.

## Prompt 2: Infra task template (scripts + docs + small commits)
Scope: scripts/docs only, no CI/workflow/Xcode changes unless asked.
Plan small steps; after each step, run the minimum validation command and commit.
Give commit messages and PR steps; keep output to key summaries and commands only.

## Prompt 3: Expected/Waiting required check triage
Read required_status_checks and compare with PR head SHA check-runs/statuses:
- gh api .../required_status_checks
- gh api .../commits/<SHA>/check-runs
- gh api .../commits/<SHA>/status
If mismatch, rebind required checks to checks-based build@15368.
Summarize before/after and propose refresh/empty-commit if needed.
