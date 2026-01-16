#!/bin/bash
# Adapter: Get Pull Request diff from GitHub
#
# Usage: ./github-get-pr-diff.sh <pr_number> [--workdir <path>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to get diff for
#   --workdir - Optional: Working directory (uses git diff if available)
#
# Output:
#   The diff content (unified diff format)

set -euo pipefail

# NOTE(angeldev)
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
    echo "Usage: $0 <pr_number> [--workdir <path>]" >&2
    exit 1
fi

PR_NUMBER="$1"
shift

WORKDIR=""

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# NOTE(angeldev)
# If workdir is provided, try to get diff from local git first (more accurate for latest changes)
if [[ -n "$WORKDIR" && -d "$WORKDIR/.git" ]]; then
    # Fetch latest from origin to ensure we have up-to-date refs
    (cd "$WORKDIR" && git fetch origin 2>/dev/null) || true
    
    # Get diff between main and current HEAD
    DIFF=$(cd "$WORKDIR" && git diff origin/main...HEAD 2>/dev/null) || DIFF=""
    
    if [[ -n "$DIFF" ]]; then
        echo "$DIFF"
        exit 0
    fi
fi

# NOTE(angeldev)
# Fall back to GitHub API to fetch the PR diff.
# Use the media type for diff format.
RESPONSE=$(curl -s \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3.diff" \
    -H "X-GitHub-Api-Version: 2022-11-28")

# NOTE(angeldev)
# Check API response for errors (diff format returns plain text, errors return JSON).
if echo "$RESPONSE" | head -1 | grep -q '^{'; then
    # Response is JSON, likely an error
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // empty' 2>/dev/null)
    if [[ -n "$ERROR_MSG" ]]; then
        echo "ERROR: Failed to get pull request diff #${PR_NUMBER}: $ERROR_MSG" >&2
        exit 1
    fi
fi

echo "$RESPONSE"
