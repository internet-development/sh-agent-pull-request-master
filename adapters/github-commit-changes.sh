#!/bin/bash
# Adapter: Commit and push changes to the current branch
#
# Usage: ./github-commit-changes.sh <message> [--files <file1> <file2> ...] [--workdir <path>]
#
# Environment variables required:
#   GITHUB_TOKEN - GitHub personal access token (for push)
#   GITHUB_USERNAME - GitHub username for commit attribution
#
# Arguments:
#   message - Commit message
#   --files - Optional specific files to commit (default: all changes)
#   --all - Stage all changes including untracked files
#   --workdir - Working directory (the cloned target repo)

set -euo pipefail

# NOTE(jimmylee)
# Validate required environment variables before proceeding.
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: GITHUB_TOKEN environment variable is not set" >&2
    exit 1
fi

# NOTE(jimmylee)
# Parse command line arguments for commit message and optional file selection.
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <message> [--files <file1> <file2> ...] [--all] [--workdir <path>]" >&2
    exit 1
fi

MESSAGE="$1"
shift

FILES=()
STAGE_ALL=false
WORKDIR=""

# NOTE(jimmylee)
# Parse optional --files, --all, and --workdir flags.
while [[ $# -gt 0 ]]; do
    case $1 in
        --files)
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                FILES+=("$1")
                shift
            done
            ;;
        --all)
            STAGE_ALL=true
            shift
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
# Check if there are any changes to commit before proceeding.
if [[ -z $(git status --porcelain) ]]; then
    echo "No changes to commit"
    exit 0
fi

# NOTE(jimmylee)
# Stage changes based on provided options: specific files, all, or modified only.
if [[ ${#FILES[@]} -gt 0 ]]; then
    echo "Staging specified files..."
    git add "${FILES[@]}"
elif [[ "$STAGE_ALL" == true ]]; then
    echo "Staging all changes..."
    git add -A
else
    echo "Staging modified and deleted files..."
    git add -u
fi

# NOTE(jimmylee)
# Verify there are staged changes before attempting commit.
if [[ -z $(git diff --cached --name-only) ]]; then
    echo "No staged changes to commit"
    exit 0
fi

# NOTE(jimmylee)
# Create commit with the provided message.
echo "Creating commit..."
git commit -m "$MESSAGE"

# NOTE(jimmylee)
# Get current branch.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# NOTE(jimmylee)
# Build authenticated push URL directly to bypass credential helper issues.
# This ensures we always use the token from the environment.
if [[ -z "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" ]]; then
    echo "ERROR: GITHUB_REPO_AGENTS_WILL_WORK_ON environment variable is not set" >&2
    exit 1
fi

AUTH_PUSH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO_AGENTS_WILL_WORK_ON}.git"

# NOTE(angeldev)
# Retry configuration for push operations.
MAX_PUSH_RETRIES="${MAX_PUSH_RETRIES:-3}"
RETRY_DELAY=2

# NOTE(angeldev)
# Push with exponential backoff retry logic.
# Handles transient network errors, rate limits, and auth issues.
push_with_retry() {
    local attempt=1
    local delay=$RETRY_DELAY

    while [[ $attempt -le $MAX_PUSH_RETRIES ]]; do
        echo "Push attempt $attempt/$MAX_PUSH_RETRIES..."

        local push_output
        local push_status=0
        push_output=$(git push "$AUTH_PUSH_URL" "$CURRENT_BRANCH" 2>&1) || push_status=$?

        if [[ $push_status -eq 0 ]]; then
            return 0
        fi

        # Analyze failure mode
        if echo "$push_output" | grep -qi "nothing to push\|up.to.date\|Everything up-to-date"; then
            echo "Nothing to push - already up to date"
            return 0
        fi

        if echo "$push_output" | grep -qi "authentication\|401\|403\|permission denied"; then
            echo "ERROR: Authentication failed - check GITHUB_TOKEN permissions" >&2
            echo "$push_output" >&2
            return 1
        fi

        if echo "$push_output" | grep -qi "non-fast-forward\|rejected\|failed to push"; then
            echo "WARNING: Push rejected - attempting to pull and retry..."

            # Try to pull with rebase
            if git pull --rebase "$AUTH_PUSH_URL" "$CURRENT_BRANCH" 2>/dev/null; then
                echo "Pulled successfully, retrying push..."
                ((attempt++))
                continue
            else
                echo "ERROR: Pull rebase failed - manual intervention needed" >&2
                echo "$push_output" >&2
                return 1
            fi
        fi

        if echo "$push_output" | grep -qi "rate limit\|429\|too many requests"; then
            echo "WARNING: Rate limited, waiting ${delay}s before retry..."
            sleep "$delay"
            delay=$((delay * 2))
            ((attempt++))
            continue
        fi

        if echo "$push_output" | grep -qi "connection\|network\|timeout\|could not resolve"; then
            echo "WARNING: Network error, waiting ${delay}s before retry..."
            sleep "$delay"
            delay=$((delay * 2))
            ((attempt++))
            continue
        fi

        # Unknown error on last attempt
        if [[ $attempt -ge $MAX_PUSH_RETRIES ]]; then
            echo "ERROR: Push failed after $MAX_PUSH_RETRIES attempts" >&2
            echo "$push_output" >&2
            return 1
        fi

        echo "WARNING: Push failed, retrying in ${delay}s..."
        echo "$push_output"
        sleep "$delay"
        delay=$((delay * 2))
        ((attempt++))
    done

    return 1
}

# NOTE(jimmylee)
# Push directly to authenticated URL to bypass any credential caching.
echo "Pushing to origin/$CURRENT_BRANCH..."
if push_with_retry; then
    echo "SUCCESS: Changes committed and pushed"
    echo "Commit: $(git rev-parse --short HEAD)"
    echo "Branch: $CURRENT_BRANCH"
else
    echo "ERROR: Failed to push changes" >&2
    exit 1
fi
