#!/bin/bash
# Adapter: Approve a Pull Request on GitHub
#
# Usage: ./github-approve-pr.sh <pr_number> [comment] [--persona <persona_name>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to approve
#   comment - Optional approval comment (default: "LGTM")
#   --persona - Optional persona name to prefix the comment
#
# Note: This adapter creates an APPROVE review. It does NOT merge the PR.

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
# Parse command line arguments for PR number, comment, and optional persona.
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <pr_number> [comment] [--persona <persona_name>]" >&2
    exit 1
fi

PR_NUMBER="$1"
shift

COMMENT="LGTM"
PERSONA=""

# NOTE(jimmylee)
# Parse remaining arguments for optional comment and persona flag.
while [[ $# -gt 0 ]]; do
    case $1 in
        --persona)
            PERSONA="$2"
            shift 2
            ;;
        *)
            # First non-flag argument is the comment
            if [[ "$1" != --* ]]; then
                COMMENT="$1"
                shift
            else
                echo "Unknown option: $1" >&2
                exit 1
            fi
            ;;
    esac
done

# NOTE(jimmylee)
# Format the approval comment with persona prefix if provided.
if [[ -n "$PERSONA" ]]; then
    FORMATTED_COMMENT="**[$PERSONA]**

$COMMENT"
else
    FORMATTED_COMMENT="$COMMENT"
fi

# NOTE(jimmylee)
# Escape the comment for safe JSON embedding.
ESCAPED_COMMENT=$(json_escape "$FORMATTED_COMMENT")

# NOTE(jimmylee)
# Submit PR approval via GitHub REST API. Creates an APPROVE review event.
echo "Approving pull request #$PR_NUMBER..."
echo "Note: This will NOT merge the PR. A human must manually merge."

RESPONSE=$(curl -s -X POST \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/pulls/${PR_NUMBER}/reviews" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "{
        \"body\": \"${ESCAPED_COMMENT}\",
        \"event\": \"APPROVE\"
    }")

# NOTE(jimmylee)
# Check API response for errors and extract error message if present.
if echo "$RESPONSE" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "ERROR: Failed to approve pull request #$PR_NUMBER" >&2
    echo "GitHub API response: $ERROR_MSG" >&2
    exit 1
fi

# NOTE(jimmylee)
# Verify successful response and extract review URL for user feedback.
if echo "$RESPONSE" | grep -q '"id"'; then
    REVIEW_URL=$(echo "$RESPONSE" | grep -o '"html_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "SUCCESS: Pull request #$PR_NUMBER approved"
    echo "Review URL: $REVIEW_URL"
    echo "IMPORTANT: PR is NOT merged. Human verification and merge required."
else
    echo "ERROR: Unexpected response from GitHub API" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
