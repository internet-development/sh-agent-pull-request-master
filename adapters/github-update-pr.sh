#!/bin/bash
# Adapter: Update an existing Pull Request on GitHub
#
# Usage: ./github-update-pr.sh <pr_number> [--title <title>] [--body <body>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to update
#   --title - New title (optional)
#   --body - New body (optional)

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
# Parse command line arguments for PR number, title, and body.
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <pr_number> [--title <title>] [--body <body>]" >&2
    exit 1
fi

PR_NUMBER="$1"
shift

TITLE=""
BODY=""

# NOTE(jimmylee)
# Parse optional --title and --body flags.
while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --body)
            BODY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$TITLE" && -z "$BODY" ]]; then
    echo "ERROR: At least one of --title or --body must be provided" >&2
    exit 1
fi

# NOTE(jimmylee)
# Build JSON payload dynamically based on provided options.
PAYLOAD="{"
FIRST=true

if [[ -n "$TITLE" ]]; then
    ESCAPED_TITLE=$(json_escape "$TITLE")
    PAYLOAD="${PAYLOAD}\"title\": \"${ESCAPED_TITLE}\""
    FIRST=false
fi

if [[ -n "$BODY" ]]; then
    ESCAPED_BODY=$(json_escape "$BODY")
    if [[ "$FIRST" == false ]]; then
        PAYLOAD="${PAYLOAD}, "
    fi
    PAYLOAD="${PAYLOAD}\"body\": \"${ESCAPED_BODY}\""
fi

PAYLOAD="${PAYLOAD}}"

# NOTE(jimmylee)
# Update PR via GitHub REST API using PATCH request.
echo "Updating pull request #$PR_NUMBER..."

RESPONSE=$(curl -s -X PATCH \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$PAYLOAD")

# NOTE(jimmylee)
# Check API response for errors and extract error message if present.
if echo "$RESPONSE" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "ERROR: Failed to update pull request #$PR_NUMBER" >&2
    echo "GitHub API response: $ERROR_MSG" >&2
    exit 1
fi

# NOTE(jimmylee)
# Verify successful response and extract PR URL for user feedback.
if echo "$RESPONSE" | grep -q '"number"'; then
    PR_URL=$(echo "$RESPONSE" | grep -o '"html_url"[[:space:]]*:[[:space:]]*"[^"]*pull[^"]*"' | head -1 | sed 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "SUCCESS: Pull request #$PR_NUMBER updated"
    echo "URL: $PR_URL"
else
    echo "ERROR: Unexpected response from GitHub API" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
