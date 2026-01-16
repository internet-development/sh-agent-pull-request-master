#!/bin/bash
# Adapter: Clone the target repository to a working directory
#
# Usage: ./git-clone-repo.sh [--clean]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token
#   GITHUB_REPO_AGENTS_WILL_WORK_ON - Target repository (owner/repo format)
#
# Arguments:
#   --clean - Remove existing clone and start fresh
#
# The repository will be cloned to .workrepo/{repo-name}/ relative to the agent root.
# Returns the path to the cloned repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKDIR="${AGENT_ROOT}/.workrepo"

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

CLEAN=false

# NOTE(jimmylee)
# Parse optional --clean flag to force fresh clone.
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# NOTE(jimmylee)
# Extract repo name from owner/repo format for directory naming.
REPO_OWNER=$(echo "$GITHUB_REPO_AGENTS_WILL_WORK_ON" | cut -d'/' -f1)
REPO_NAME=$(echo "$GITHUB_REPO_AGENTS_WILL_WORK_ON" | cut -d'/' -f2)
CLONE_PATH="${WORKDIR}/${REPO_NAME}"

# NOTE(jimmylee)
# Handle --clean flag: remove existing clone if requested.
if [[ "$CLEAN" == true && -d "$CLONE_PATH" ]]; then
    echo "Removing existing clone at $CLONE_PATH..."
    rm -rf "$CLONE_PATH"
fi

# NOTE(jimmylee)
# Create workdir if it doesn't exist.
mkdir -p "$WORKDIR"

# NOTE(jimmylee)
# Build the authenticated URL - use x-access-token format for fine-grained PATs.
# Format: https://x-access-token:TOKEN@github.com/owner/repo.git
AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO_AGENTS_WILL_WORK_ON}.git"

# NOTE(jimmylee)
# Clone or update the repository.
if [[ -d "$CLONE_PATH/.git" ]]; then
    echo "Repository already cloned at $CLONE_PATH"
    cd "$CLONE_PATH"

    # NOTE(angeldev)
    # ALWAYS do a fresh clone if --clean was passed, even if .git exists.
    # This ensures truly fresh state with no stale content.
    if [[ "$CLEAN" == true ]]; then
        echo "Clean flag set - removing and re-cloning for fresh state..."
        cd "$WORKDIR"
        rm -rf "$CLONE_PATH"
        git clone "$AUTH_URL" "$CLONE_PATH"
        cd "$CLONE_PATH"
        git config credential.helper ""
        echo "Fresh clone complete"
    else
        # NOTE(jimmylee)
        # Always update the remote URL to ensure token is current.
        # This fixes issues where the token may have changed or macOS keychain interferes.
        echo "Updating remote URL with current token..."
        git remote set-url origin "$AUTH_URL"

        # Disable credential helper for this repo to prevent macOS keychain interference
        git config credential.helper ""

        echo "Fetching latest changes..."
        git fetch origin --prune

        # Reset to main/master to ensure clean state
        DEFAULT_BRANCH=$(git remote show origin | grep "HEAD branch" | cut -d: -f2 | tr -d ' ')
        if [[ -z "$DEFAULT_BRANCH" ]]; then
            DEFAULT_BRANCH="main"
        fi

        echo "Resetting to origin/$DEFAULT_BRANCH..."

        # NOTE(jimmylee)
        # Hard reset to ensure we have a completely clean state.
        # This removes any local changes, stashed changes, and untracked files.
        git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
        git reset --hard "origin/$DEFAULT_BRANCH"
        git clean -fdx  # Remove untracked files, directories, AND ignored files

        echo "Repository reset to latest origin/$DEFAULT_BRANCH"
    fi
else
    echo "Cloning ${GITHUB_REPO_AGENTS_WILL_WORK_ON} to ${CLONE_PATH}..."
    
    git clone "$AUTH_URL" "$CLONE_PATH"
    
    cd "$CLONE_PATH"
    
    # NOTE(jimmylee)
    # Disable credential helper to prevent macOS keychain from overriding our token.
    git config credential.helper ""
fi

# NOTE(jimmylee)
# Always configure git user for commits in this repo.
if [[ -n "${GITHUB_USERNAME:-}" ]]; then
    git config user.name "$GITHUB_USERNAME"
    git config user.email "${GITHUB_USERNAME}@users.noreply.github.com"
fi

echo "SUCCESS: Repository ready at $CLONE_PATH"
echo "CLONE_PATH: $CLONE_PATH"
