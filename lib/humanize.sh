#!/bin/bash
#
# NOTE(angeldev)
# Comment accumulation utilities for GitHub PR reviews.
# Maintains conversational continuity across persona reviews by persisting
# humanized comments to file storage (survives subshell boundaries).
#
# The actual humanization (transforming structured output to prose) is done by
# humanize_for_github() in lib/providers.sh using GPT-5.

[[ -n "${_HUMANIZE_SH_LOADED:-}" ]] && return 0
_HUMANIZE_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# NOTE(angeldev)
# Global variable to track previous humanized comments across persona reviews.
# This maintains conversational continuity and enables variety in tone.
PREVIOUS_HUMANIZED_COMMENTS=""

# NOTE(angeldev)
# File-based storage for humanized comments to survive subshell boundaries.
HUMANIZED_COMMENTS_FILE="${STATE_DIR:-/tmp}/humanized_comments.txt"

# NOTE(angeldev)
# Appends a humanized comment to the persistent file storage.
# This ensures comments survive subshell boundaries and accumulate correctly.
append_humanized_comment() {
    local comment="$1"
    if [[ -n "$comment" ]]; then
        echo "---" >> "$HUMANIZED_COMMENTS_FILE"
        echo "$comment" >> "$HUMANIZED_COMMENTS_FILE"
        echo "---" >> "$HUMANIZED_COMMENTS_FILE"
    fi
}

# NOTE(angeldev)
# Reads all accumulated humanized comments from file storage.
# Returns empty string if no comments exist yet.
get_accumulated_comments() {
    if [[ -f "$HUMANIZED_COMMENTS_FILE" ]]; then
        cat "$HUMANIZED_COMMENTS_FILE"
    else
        echo ""
    fi
}

# NOTE(angeldev)
# Resets the humanized comments file for a new review session.
reset_humanized_comments() {
    rm -f "$HUMANIZED_COMMENTS_FILE"
    touch "$HUMANIZED_COMMENTS_FILE"
    PREVIOUS_HUMANIZED_COMMENTS=""
}

# NOTE(angeldev)
# Gets the raw accumulated review feedback for humanization.
# Returns the cleaned content without formatting - GPT will create a natural reflection.
# Returns empty string if no comments have been accumulated.
get_review_summary() {
    local accumulated
    accumulated=$(get_accumulated_comments)

    if [[ -z "$accumulated" || "$accumulated" == "---" ]]; then
        echo ""
        return 0
    fi

    # Count the number of feedback entries (separated by ---)
    local entry_count
    entry_count=$(echo "$accumulated" | grep -c "^---$" || echo "0")
    entry_count=$((entry_count / 2))  # Each entry has opening and closing ---

    if [[ $entry_count -eq 0 ]]; then
        echo ""
        return 0
    fi

    # Return cleaned content - GPT will humanize this into a single reflection
    echo "$accumulated" | sed '/^---$/d' | sed '/^$/d'
}
