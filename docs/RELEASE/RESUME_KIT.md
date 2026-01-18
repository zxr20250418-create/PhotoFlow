# Resume Kit

Start here next time
1) git switch main && git pull --ff-only
2) Read docs/RELEASE/RELEASE_FREEZE.md
3) Read docs/AGENTS/queue.md
4) List open PRs

Hard rules
- Write a plan before coding
- Only change allowed files per task
- Run ios_safe and attach PASS output
- Heavy computations must not run in startup paths or synchronously in View body

Open issues
- Widget/complication timer still not resolved. Track PR #136 (risk: RISKY due to watch/widget + config/entitlement changes).
