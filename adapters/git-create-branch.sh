#!/bin/bash
# Adapter: Create a new git branch following naming conventions
#
# Usage: ./git-create-branch.sh <title> [--base <base_branch>] [--workdir <path>]
#
# Environment variables required:
#   GITHUB_USERNAME - GitHub username for branch naming
#
# Arguments:
#   title - The title/description for the branch (will be slugified)
#   --base - Base branch to create from (default: main)
#   --workdir - Working directory (the cloned target repo)
#
# Branch naming convention: @{username}/{slug-lowercase-title}

set -euo pipefail

# NOTE(jimmylee)
# Validate required environment variables before proceeding.
if [[ -z "${GITHUB_USERNAME:-}" ]]; then
    echo "ERROR: GITHUB_USERNAME environment variable is not set" >&2
    exit 1
fi

# NOTE(jimmylee)
# Parse command line arguments for title and optional base branch.
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <title> [--base <base_branch>] [--workdir <path>]" >&2
    exit 1
fi

TITLE="$1"
shift

BASE_BRANCH="main"
WORKDIR=""

# NOTE(jimmylee)
# Parse optional --base and --workdir flags.
while [[ $# -gt 0 ]]; do
    case $1 in
        --base)
            BASE_BRANCH="$2"
            shift 2
            ;;
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
# Slugify the title for branch naming.
# Converts to lowercase, replaces special chars with hyphens, limits length.
slugify() {
    echo "$1" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-//' | \
        sed 's/-$//' | \
        cut -c1-30  # Keep branch names short
}

SLUG=$(slugify "$TITLE")

# NOTE(jimmylee)
# Validate that we have a valid slug - fallback to timestamp if empty
if [[ -z "$SLUG" ]]; then
    echo "WARNING: Empty slug from title '$TITLE', using timestamp fallback" >&2
    SLUG="feature-$(date +%Y%m%d-%H%M%S)"
fi

BRANCH_NAME="@${GITHUB_USERNAME}/${SLUG}"

# NOTE(jimmylee)
# Create branch following naming convention: @{username}/{slug-lowercase-title}
echo "Creating branch: $BRANCH_NAME"
echo "Base branch: $BASE_BRANCH"

# NOTE(jimmylee)
# Fetch latest from remote to ensure we branch from up-to-date base.
echo "Fetching latest from origin..."
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
git fetch origin 2>/dev/null || true

# NOTE(jimmylee)
# Build authenticated URL for remote operations (delete remote branch).
AUTH_URL="https://x-access-token:${GITHUB_TOKEN:-}@github.com/${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}.git"

# NOTE(jimmylee)
# Delete existing branch (both local and remote) to ensure fresh start.
# This handles cases where a previous run failed and left stale branches.
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "Branch '$BRANCH_NAME' exists locally, deleting for fresh start..."
    git checkout "$BASE_BRANCH" 2>/dev/null || git checkout "origin/$BASE_BRANCH" --detach
    git branch -D "$BRANCH_NAME" 2>/dev/null || true
fi

if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
    echo "Branch '$BRANCH_NAME' exists on remote, deleting for fresh start..."
    if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" ]]; then
        git push "$AUTH_URL" --delete "$BRANCH_NAME" 2>/dev/null || true
    else
        git push origin --delete "$BRANCH_NAME" 2>/dev/null || true
    fi
fi

# NOTE(jimmylee)
# Create and checkout new branch from latest base.
echo "Creating new branch from origin/$BASE_BRANCH..."
if git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
    git checkout -b "$BRANCH_NAME" "origin/$BASE_BRANCH"
else
    echo "Warning: origin/$BASE_BRANCH not found, using local $BASE_BRANCH"
    git checkout -b "$BRANCH_NAME" "$BASE_BRANCH"
fi

echo "SUCCESS: Now on branch '$BRANCH_NAME'"
echo "BRANCH_NAME: $BRANCH_NAME"
