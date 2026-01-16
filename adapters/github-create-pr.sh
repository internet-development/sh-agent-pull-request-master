#!/bin/bash
# Adapter: Create a Pull Request on GitHub
# 
# Usage: ./github-create-pr.sh <title> <body> [base_branch] [--workdir <path>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   title - PR title
#   body - PR description (can be multiline)
#   base_branch - Base branch to merge into (default: main)
#   --workdir - Working directory (the cloned target repo)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source shared JSON handling library
source "${LIB_DIR}/json.sh"

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
# Parse command line arguments for title, body, base branch, and workdir.
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <title> <body> [base_branch] [--workdir <path>]" >&2
    exit 1
fi

TITLE="$1"
BODY="$2"
shift 2

BASE_BRANCH="main"
WORKDIR=""

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            # First positional arg after title/body is base_branch
            BASE_BRANCH="$1"
            shift
            ;;
    esac
done

# NOTE(jimmylee)
# Change to working directory if specified.
if [[ -n "$WORKDIR" ]]; then
    if [[ ! -d "$WORKDIR" ]]; then
        echo "ERROR: Working directory does not exist: $WORKDIR" >&2
        exit 1
    fi
    cd "$WORKDIR"
    echo "Working in: $WORKDIR"
fi

# NOTE(jimmylee)
# Get current branch name and validate it's not the base branch.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
    echo "ERROR: Cannot create PR from base branch '$BASE_BRANCH'" >&2
    exit 1
fi

# NOTE(jimmylee)
# Build authenticated push URL directly to bypass credential helper issues.
AUTH_PUSH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO_AGENTS_WILL_WORK_ON}.git"

# NOTE(jimmylee)
# Ensure branch is pushed to remote before creating PR.
# Push directly to authenticated URL to bypass any credential caching.
echo "Ensuring branch '$CURRENT_BRANCH' is pushed to origin..."
git push "$AUTH_PUSH_URL" "$CURRENT_BRANCH" 2>/dev/null || git push "$AUTH_PUSH_URL" "$CURRENT_BRANCH"

# NOTE(jimmylee)
# Check if there are any commits that differ from base branch.
# GitHub will reject PR creation if there are no changes.
COMMITS_AHEAD=$(git rev-list --count "origin/${BASE_BRANCH}..HEAD" 2>/dev/null || echo "0")
if [[ "$COMMITS_AHEAD" == "0" ]]; then
    echo "ERROR: No commits ahead of ${BASE_BRANCH}. Cannot create PR without changes." >&2
    echo "This usually means the Engineer's code changes were not applied or committed." >&2
    exit 1
fi

echo "Branch has $COMMITS_AHEAD commit(s) ahead of $BASE_BRANCH"

# NOTE(jimmylee)
# Escape title and body for safe JSON embedding.
ESCAPED_TITLE=$(json_escape "$TITLE")
ESCAPED_BODY=$(json_escape "$BODY")

# NOTE(jimmylee)
# Create PR via GitHub REST API using POST request.
echo "Creating pull request..."

RESPONSE=$(curl -s -X POST \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "{
        \"title\": \"${ESCAPED_TITLE}\",
        \"body\": \"${ESCAPED_BODY}\",
        \"head\": \"${CURRENT_BRANCH}\",
        \"base\": \"${BASE_BRANCH}\"
    }")

# NOTE(jimmylee)
# Check API response for errors. Handle existing PR case gracefully.
if echo "$RESPONSE" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    
    # Check if PR already exists
    if echo "$ERROR_MSG" | grep -qi "already exists"; then
        echo "Note: A pull request already exists for this branch"
        # Try to get existing PR
        EXISTING_PR=$(curl -s \
            "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls?head=${CURRENT_BRANCH}&state=open" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json")
        
        PR_NUMBER=$(echo "$EXISTING_PR" | grep -o '"number"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*:[[:space:]]*//')
        PR_URL=$(echo "$EXISTING_PR" | grep -o '"html_url"[[:space:]]*:[[:space:]]*"[^"]*pull[^"]*"' | head -1 | sed 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        
        if [[ -n "$PR_NUMBER" ]]; then
            echo "SUCCESS: Using existing pull request"
            echo "URL: $PR_URL"
            echo "PR_NUMBER: $PR_NUMBER"
            exit 0
        fi
    fi
    
    echo "ERROR: Failed to create pull request" >&2
    echo "GitHub API response: $ERROR_MSG" >&2
    # Show full response for debugging validation errors
    echo "Full response: $RESPONSE" >&2
    exit 1
fi

# NOTE(jimmylee)
# Extract PR URL and number from successful response.
PR_URL=$(echo "$RESPONSE" | grep -o '"html_url"[[:space:]]*:[[:space:]]*"[^"]*pull[^"]*"' | head -1 | sed 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
PR_NUMBER=$(echo "$RESPONSE" | grep -o '"number"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*:[[:space:]]*//')

if [[ -n "$PR_URL" && -n "$PR_NUMBER" ]]; then
    echo "SUCCESS: Pull request created"
    echo "URL: $PR_URL"
    echo "PR_NUMBER: $PR_NUMBER"
else
    echo "ERROR: Failed to parse pull request response" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
