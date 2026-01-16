#!/bin/bash
# Adapter: Get Pull Request details from GitHub
#
# Usage: ./github-get-pr.sh <pr_number>
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to get details for
#
# Output:
#   JSON with PR details including number, url, title, state, head SHA, etc.

set -euo pipefail

# NOTE(jimmylee)
# Validate required environment variables before proceeding.
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: GITHUB_TOKEN environment variable is not set" >&2
    exit 1
fi

if [[ -z "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" ]]; then
    echo "ERROR: GITHUB_REPO_AGENTS_WILL_WORK_ON environment variable is not set" >&2
    exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <pr_number>" >&2
    exit 1
fi

PR_NUMBER="$1"

# NOTE(jimmylee)
# Fetch PR details via GitHub REST API.
RESPONSE=$(curl -s \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28")

# NOTE(jimmylee)
# Check API response for errors.
if echo "$RESPONSE" | grep -q '"message"'; then
    # Check if it's actually an error (not just a field in the response)
    if echo "$RESPONSE" | jq -e 'if type == "object" and has("message") and (has("documentation_url") or .message == "Not Found") then true else false end' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // empty' 2>/dev/null)
        echo "ERROR: Failed to get pull request #${PR_NUMBER}: $ERROR_MSG" >&2
        exit 1
    fi
fi

# NOTE(jimmylee)
# Format output as simplified JSON.
if command -v jq &> /dev/null; then
    echo "$RESPONSE" | jq '{
        number: .number,
        url: .html_url,
        title: .title,
        state: .state,
        head_sha: .head.sha,
        head_ref: .head.ref,
        base_ref: .base.ref,
        mergeable: .mergeable,
        merged: .merged,
        draft: .draft
    }'
else
    echo "$RESPONSE"
fi
