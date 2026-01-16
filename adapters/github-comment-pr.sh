#!/bin/bash
# Adapter: Add a comment to a Pull Request on GitHub
#
# Usage: ./github-comment-pr.sh <pr_number> <comment> [--persona <persona_name>] [--skip-humanize] [--previous-comments <text>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   pr_number - The PR number to comment on
#   comment - The comment text
#   --persona - Optional persona name to prefix the comment
#   --skip-humanize - Skip GPT-5 humanization (for simple comments like "LGTM")
#   --previous-comments - Previous comments for context (ensures variety in tone)

set -euo pipefail

# NOTE(jimmylee)
# Determine the adapter and library directories for sourcing dependencies.
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${ADAPTER_DIR}/../lib"

# NOTE(jimmylee)
# Source shared libraries for JSON handling and comment humanization.
source "${LIB_DIR}/json.sh"

if [[ -f "${LIB_DIR}/providers.sh" ]]; then
    source "${LIB_DIR}/providers.sh"
    HUMANIZE_AVAILABLE=true
else
    HUMANIZE_AVAILABLE=false
fi

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
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <pr_number> <comment> [--persona <persona_name>]" >&2
    exit 1
fi

PR_NUMBER="$1"
COMMENT="$2"
shift 2

PERSONA=""
SKIP_HUMANIZE=false
PREVIOUS_COMMENTS=""

# NOTE(jimmylee)
# Parse optional flags for persona, humanization control, and previous comments.
while [[ $# -gt 0 ]]; do
    case $1 in
        --persona)
            PERSONA="$2"
            shift 2
            ;;
        --skip-humanize)
            SKIP_HUMANIZE=true
            shift
            ;;
        --previous-comments)
            PREVIOUS_COMMENTS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# NOTE(jimmylee)
# Log the original comment before any transformation.
# This preserves the structured markdown in logs while GitHub gets the humanized version.
echo "ORIGINAL_COMMENT:"
echo "$COMMENT"
echo "---"

# NOTE(jimmylee)
# Humanize the comment using GPT-5 before posting to GitHub.
# This transforms structured markdown into natural, introspective prose.
# Skip humanization for short/simple comments or if explicitly requested.
FORMATTED_COMMENT="$COMMENT"

if [[ "$SKIP_HUMANIZE" == "false" && "$HUMANIZE_AVAILABLE" == "true" ]]; then
    # Skip humanization for very short comments (like "LGTM", single lines)
    COMMENT_LENGTH=${#COMMENT}
    COMMENT_LINES=$(echo "$COMMENT" | wc -l | tr -d ' ')
    
    if [[ $COMMENT_LENGTH -gt 50 && $COMMENT_LINES -gt 1 ]]; then
        echo "Humanizing comment with GPT-5..."
        HUMANIZED=$(humanize_for_github "$COMMENT" "$PREVIOUS_COMMENTS" 2>/dev/null) || HUMANIZED=""
        
        if [[ -n "$HUMANIZED" && "$HUMANIZED" != "$COMMENT" ]]; then
            FORMATTED_COMMENT="$HUMANIZED"
            echo "HUMANIZED_COMMENT:"
            echo "$FORMATTED_COMMENT"
            echo "---"
        else
            echo "Using original comment (humanization returned empty or unchanged)"
        fi
    else
        echo "Skipping humanization for short comment"
    fi
elif [[ "$SKIP_HUMANIZE" == "true" ]]; then
    echo "Humanization explicitly skipped"
fi

# NOTE(jimmylee)
# Escape the comment for safe JSON embedding.
ESCAPED_COMMENT=$(json_escape "$FORMATTED_COMMENT")

# NOTE(jimmylee)
# Add comment via GitHub REST API. Uses issues endpoint which works for PR comments.
echo "Adding comment to pull request #$PR_NUMBER..."

RESPONSE=$(curl -s -X POST \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/issues/${PR_NUMBER}/comments" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "{\"body\": \"${ESCAPED_COMMENT}\"}")

# NOTE(jimmylee)
# Check API response for errors and extract error message if present.
if echo "$RESPONSE" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "ERROR: Failed to add comment to pull request #$PR_NUMBER" >&2
    echo "GitHub API response: $ERROR_MSG" >&2
    exit 1
fi

# NOTE(jimmylee)
# Verify successful response and extract comment ID and URL for user feedback.
if echo "$RESPONSE" | grep -q '"id"'; then
    COMMENT_ID=$(echo "$RESPONSE" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
    COMMENT_URL=$(echo "$RESPONSE" | grep -o '"html_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "SUCCESS: Comment added to pull request #$PR_NUMBER"
    echo "COMMENT_ID: $COMMENT_ID"
    echo "URL: $COMMENT_URL"
else
    echo "ERROR: Unexpected response from GitHub API" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
