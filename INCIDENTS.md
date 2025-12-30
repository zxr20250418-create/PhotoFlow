# Incidents

## Template (copy/paste)
Date:
Title:
Impact:
User-visible symptom:
Root cause:
Trigger / Change:
Detection:
Fix:
Prevention:
Refs (issue/commit/tag):

## Date: 2025-12-31
Title: Required check stuck at “Expected — Waiting for status to be reported” despite Actions success

Impact:
- PR merge blocked (required check showed 1 expected + successful checks)
- Required check appeared duplicated by name: one Successful, one Expected

User-visible symptom:
- On PR #4, “CI / build (pull_request)” showed:
  - Successful (from GitHub Actions)
  - Expected — Waiting for status to be reported (Required)
- Merge was blocked unless bypassed

Root cause:
- Branch protection required_status_checks was misconfigured/mixed:
  - “contexts” (legacy commit status) required a status context that never got reported
  - “checks” (check-runs) were reported by GitHub Actions
- Same/related names could exist across different reporting mechanisms, causing duplicate UI lines and a perpetual “Expected”.

Fix:
- Switched required checks to checks-based mode and bound to GitHub Actions app:
  - checks: [{ context: "build", app_id: 15368 }]
  - strict: true
  - contexts aligned to "build" (GitHub may keep contexts for compatibility)
- Hardened scripts/protect_main.sh to enforce and validate checks-based required status.

Prevention:
- Use checks-based required status (checks+app_id) for GitHub Actions; avoid relying on UI dropdown.
- After any CI/workflow naming change, run:
  - bash scripts/protect_main.sh
  - gh api .../required_status_checks to confirm checks=build@15368
- When PR shows “Successful + Expected”, diagnose by comparing:
  - required_status_checks (contexts vs checks)
  - PR head SHA check-runs vs statuses

Refs:
- PR #4 (stuck Expected/Waiting)
- PR #6 (merged fix; protect_main hardened)
- scripts/protect_main.sh (main)
