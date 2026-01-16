#!/bin/bash
# Adapter: Add a reviewer to a Pull Request on GitHub
#
# Usage: ./github-add-reviewer.sh <pr_number> <username>
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to add reviewer to
#   username - The GitHub username to add as reviewer

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

# NOTE(jimmylee)
# Parse command line arguments for PR number and username.
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <pr_number> <username>" >&2
    exit 1
fi

PR_NUMBER="$1"
USERNAME="$2"

# NOTE(jimmylee)
# Add reviewer via GitHub REST API.
echo "Adding $USERNAME as reviewer to PR #$PR_NUMBER..."

RESPONSE=$(curl -s -X POST \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}/requested_reviewers" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "{
        \"reviewers\": [\"${USERNAME}\"]
    }")

# NOTE(jimmylee)
# Check API response for errors and extract error message if present.
if echo "$RESPONSE" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    # Not all errors are fatal - user might already be a reviewer
    if echo "$ERROR_MSG" | grep -qi "already"; then
        echo "INFO: $USERNAME is already a reviewer"
        echo "SUCCESS: Reviewer check complete"
        exit 0
    fi
    echo "WARNING: Could not add reviewer: $ERROR_MSG" >&2
    exit 0
fi

# NOTE(jimmylee)
# Verify successful response.
if echo "$RESPONSE" | grep -q '"url"'; then
    echo "SUCCESS: Added $USERNAME as reviewer to PR #$PR_NUMBER"
else
    echo "WARNING: Unexpected response from GitHub API" >&2
    exit 0
fi
