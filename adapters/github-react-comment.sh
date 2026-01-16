#!/bin/bash
# Adapter: Add an emoji reaction to a PR comment on GitHub
#
# Usage: ./github-react-comment.sh <comment_id> <reaction>
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   comment_id - The comment ID to react to
#   reaction - The reaction type: +1, -1, laugh, confused, heart, hooray, rocket, eyes

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
# Parse command line arguments for comment ID and reaction type.
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <comment_id> <reaction>" >&2
    echo "Reactions: +1, -1, laugh, confused, heart, hooray, rocket, eyes" >&2
    exit 1
fi

COMMENT_ID="$1"
REACTION="$2"

# NOTE(jimmylee)
# Validate reaction type is supported by GitHub API.
case "$REACTION" in
    +1|-1|laugh|confused|heart|hooray|rocket|eyes)
        ;;
    thumbsup)
        REACTION="+1"
        ;;
    thumbsdown)
        REACTION="-1"
        ;;
    *)
        echo "ERROR: Invalid reaction type: $REACTION" >&2
        echo "Valid reactions: +1, -1, laugh, confused, heart, hooray, rocket, eyes" >&2
        exit 1
        ;;
esac

# NOTE(jimmylee)
# Add reaction via GitHub REST API.
RESPONSE=$(curl -s -X POST \
    "https://api.github.com/repos/${GITHUB_REPO_AGENTS_WILL_WORK_ON}/issues/comments/${COMMENT_ID}/reactions" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "{\"content\": \"${REACTION}\"}")

# NOTE(jimmylee)
# Check API response for errors.
if echo "$RESPONSE" | grep -q '"message"'; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "ERROR: Failed to add reaction to comment #$COMMENT_ID" >&2
    echo "GitHub API response: $ERROR_MSG" >&2
    exit 1
fi

# NOTE(jimmylee)
# Verify successful response.
if echo "$RESPONSE" | grep -q '"id"'; then
    echo "SUCCESS: Added $REACTION reaction to comment #$COMMENT_ID"
else
    echo "ERROR: Unexpected response from GitHub API" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
