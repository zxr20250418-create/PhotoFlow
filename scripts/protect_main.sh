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
  "strict": true,
  "contexts": [],
  "checks": [
    { "context": "build", "app_id": 15368 }
  ]
}'

echo "$payload" | gh api -X PATCH "repos/$repo/branches/main/protection/required_status_checks" --input - --silent

strict="$(gh api "repos/$repo/branches/main/protection/required_status_checks" --jq '.strict' 2>/dev/null || true)"
contexts_json="$(gh api "repos/$repo/branches/main/protection/required_status_checks" --jq '.contexts | @json' 2>/dev/null || true)"
check_ok="$(gh api "repos/$repo/branches/main/protection/required_status_checks" --jq '.checks | map(select(.context=="build" and .app_id==15368)) | length' 2>/dev/null || true)"

if [[ "$contexts_json" != "[]" && "$contexts_json" != "[\"build\"]" ]]; then
  echo "contexts must be empty or [\"build\"]"
  exit 1
fi

if [[ "$check_ok" == "0" ]]; then
  echo "checks must include build@15368"
  exit 1
fi

if [[ "$strict" != "true" ]]; then
  echo "strict must be true"
  exit 1
fi

echo "OK strict=$strict contexts=$contexts_json checks=build@15368"
