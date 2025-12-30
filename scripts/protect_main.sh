#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh not found"
  exit 1
fi

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
if [[ -z "$repo" ]]; then
  echo "ERROR: cannot determine repo"
  exit 1
fi

payload='{
  "required_status_checks": {
    "strict": true,
    "contexts": ["CI / build (pull_request)"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null
}'

echo "$payload" | gh api -X PUT "repos/$repo/branches/main/protection" --input - --silent

contexts="$(gh api "repos/$repo/branches/main/protection/required_status_checks" -q '.contexts | @json' 2>/dev/null || true)"
echo "Required contexts: ${contexts:-<none>}"
