#!/bin/bash
# Adapter: List Pull Requests on GitHub
#
# Usage: ./github-list-prs.sh [--head <branch>] [--state <open|closed|all>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   --head - Filter by head branch name
#   --state - PR state filter (default: open)
#
# Output:
#   JSON array of PRs with number, url, title, state, head branch

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

HEAD_BRANCH=""
STATE="open"

# NOTE(jimmylee)
# Parse command line arguments.
while [[ $# -gt 0 ]]; do
    case $1 in
        --head)
            HEAD_BRANCH="$2"
            shift 2
            ;;
        --state)
            STATE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# NOTE(jimmylee)
# Build query string for the API request.
QUERY_PARAMS="state=${STATE}"
if [[ -n "$HEAD_BRANCH" ]]; then
    # GitHub API expects head in format "owner:branch" or just "branch"
    QUERY_PARAMS="${QUERY_PARAMS}&head=${GITHUB_REPO_AGENTS_WILL_WORK_ON%%/*}:${HEAD_BRANCH}"
fi

# NOTE(jimmylee)
# Fetch PRs via GitHub REST API.
RESPONSE=$(curl -s \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls?${QUERY_PARAMS}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28")

# NOTE(jimmylee)
# Check API response for errors.
if echo "$RESPONSE" | grep -q '"message"'; then
    # Check if it's actually an error (not just a field in the response)
    if echo "$RESPONSE" | jq -e 'if type == "object" and has("message") and (has("documentation_url") or .message == "Not Found") then true else false end' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // empty' 2>/dev/null)
        echo "ERROR: Failed to list pull requests: $ERROR_MSG" >&2
        exit 1
    fi
fi

# NOTE(jimmylee)
# Format output as simplified JSON array.
if command -v jq &> /dev/null; then
    echo "$RESPONSE" | jq '[.[] | {
        number: .number,
        url: .html_url,
        title: .title,
        state: .state,
        head: .head.ref,
        base: .base.ref
    }]'
else
    echo "$RESPONSE"
fi
