#!/bin/bash
# Adapter: Get reviews and comments from a Pull Request on GitHub
#
# Usage: ./github-get-pr-reviews.sh <pr_number>
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to get reviews for
#
# Outputs JSON with reviews and comments combined.

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
# Get PR reviews (APPROVE, REQUEST_CHANGES, COMMENT reviews)
echo "Fetching reviews for PR #$PR_NUMBER..." >&2

REVIEWS=$(curl -s \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}/reviews" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28")

# NOTE(jimmylee)
# Get PR comments (issue comments, not review comments)
echo "Fetching comments for PR #$PR_NUMBER..." >&2

COMMENTS=$(curl -s \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/issues/${PR_NUMBER}/comments" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28")

# NOTE(jimmylee)
# Get PR review comments (inline code comments)
echo "Fetching inline review comments for PR #$PR_NUMBER..." >&2

REVIEW_COMMENTS=$(curl -s \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}/comments" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28")

# NOTE(jimmylee)
# Check for errors in responses
if echo "$REVIEWS" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$REVIEWS" | jq -r '.message // empty' 2>/dev/null)
    if [[ -n "$ERROR_MSG" && "$ERROR_MSG" != "null" ]]; then
        echo "ERROR: Failed to fetch reviews: $ERROR_MSG" >&2
        exit 1
    fi
fi

# NOTE(jimmylee)
# Combine all feedback into a structured format using jq
if command -v jq &> /dev/null; then
    # Use jq to create a nicely structured output
    jq -n \
        --argjson reviews "$REVIEWS" \
        --argjson comments "$COMMENTS" \
        --argjson review_comments "$REVIEW_COMMENTS" \
        '{
            pr_number: '"$PR_NUMBER"',
            reviews: ($reviews | if type == "array" then map({
                id: .id,
                user: .user.login,
                state: .state,
                body: .body,
                submitted_at: .submitted_at
            }) else [] end),
            comments: ($comments | if type == "array" then map({
                id: .id,
                user: .user.login,
                body: .body,
                created_at: .created_at
            }) else [] end),
            inline_comments: ($review_comments | if type == "array" then map({
                id: .id,
                user: .user.login,
                body: .body,
                path: .path,
                line: .line,
                created_at: .created_at
            }) else [] end)
        }'
else
    # Fallback: output raw responses
    echo "{"
    echo "  \"reviews\": $REVIEWS,"
    echo "  \"comments\": $COMMENTS,"
    echo "  \"inline_comments\": $REVIEW_COMMENTS"
    echo "}"
fi
