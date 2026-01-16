#!/bin/bash
# Adapter: Apply file changes from Engineer's code output
#
# Usage: ./apply-file-changes.sh --json <json_string> --workdir <path>
#    or: ./apply-file-changes.sh --file <json_file> --workdir <path>
#    or: echo "<json>" | ./apply-file-changes.sh --stdin --workdir <path>
#
# Arguments:
#   --json <string> - JSON string containing file changes
#   --file <path> - Path to JSON file containing file changes
#   --stdin - Read JSON from stdin
#   --workdir - Working directory (the cloned target repo)
#
# Expected JSON format:
# {
#   "files": [
#     {
#       "path": "relative/path/to/file.js",
#       "action": "create|modify|delete",
#       "content": "full file content here"
#     }
#   ]
# }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# NOTE(jimmylee)
# Source logging utilities for consistent output
source "${ROOT_DIR}/lib/logging.sh"

WORKDIR=""
JSON_INPUT=""
INPUT_MODE=""

# NOTE(jimmylee)
# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            INPUT_MODE="json"
            JSON_INPUT="$2"
            shift 2
            ;;
        --file)
            INPUT_MODE="file"
            JSON_INPUT="$2"
            shift 2
            ;;
        --stdin)
            INPUT_MODE="stdin"
            shift
            ;;
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        *)
            # Legacy: first positional arg is JSON string
            if [[ -z "$INPUT_MODE" ]]; then
                INPUT_MODE="json"
                JSON_INPUT="$1"
            fi
            shift
            ;;
    esac
done

# NOTE(jimmylee)
# Change to working directory
if [[ -n "$WORKDIR" ]]; then
    if [[ ! -d "$WORKDIR" ]]; then
        echo "ERROR: Working directory does not exist: $WORKDIR" >&2
        exit 1
    fi
    cd "$WORKDIR"
    echo "Working in: $(pwd)"
fi

# NOTE(jimmylee)
# Get JSON content based on input mode
CHANGES_JSON=""
case "$INPUT_MODE" in
    json)
        CHANGES_JSON="$JSON_INPUT"
        ;;
    file)
        if [[ ! -f "$JSON_INPUT" ]]; then
            echo "ERROR: JSON file not found: $JSON_INPUT" >&2
            exit 1
        fi
        CHANGES_JSON=$(cat "$JSON_INPUT")
        ;;
    stdin)
        CHANGES_JSON=$(cat)
        ;;
    *)
        echo "ERROR: No input provided. Use --json, --file, or --stdin" >&2
        exit 1
        ;;
esac

# NOTE(jimmylee)
# Validate we have input
if [[ -z "$CHANGES_JSON" ]]; then
    echo "ERROR: Empty JSON input" >&2
    exit 1
fi

# NOTE(jimmylee)
# Validate JSON
if ! echo "$CHANGES_JSON" | jq empty 2>/dev/null; then
    echo "ERROR: Invalid JSON input" >&2
    echo "First 200 chars: ${CHANGES_JSON:0:200}" >&2
    exit 1
fi

# NOTE(jimmylee)
# Process file changes
FILES_COUNT=$(echo "$CHANGES_JSON" | jq -r '.files | length // 0' 2>/dev/null || echo "0")

echo "Found $FILES_COUNT file(s) to process"

if [[ "$FILES_COUNT" == "0" || "$FILES_COUNT" == "null" ]]; then
    echo "WARNING: No files found in JSON"
    echo "JSON keys: $(echo "$CHANGES_JSON" | jq -r 'keys | join(", ")' 2>/dev/null || echo 'unknown')"
    exit 0
fi

APPLIED=0
ERRORS=0

for i in $(seq 0 $((FILES_COUNT - 1))); do
    FILE_PATH=$(echo "$CHANGES_JSON" | jq -r ".files[$i].path")
    ACTION=$(echo "$CHANGES_JSON" | jq -r ".files[$i].action // \"modify\"")
    
    if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
        echo "WARNING: Skipping file with no path at index $i" >&2
        ((ERRORS++)) || true
        continue
    fi
    
    echo "  [$ACTION] $FILE_PATH"
    
    case "$ACTION" in
        create|modify)
            # Create directory if needed
            DIR=$(dirname "$FILE_PATH")
            if [[ "$DIR" != "." && ! -d "$DIR" ]]; then
                mkdir -p "$DIR"
                echo "    Created directory: $DIR"
            fi
            
            # Extract and write content
            # Use jq to properly handle escaped characters in JSON strings
            if echo "$CHANGES_JSON" | jq -e ".files[$i].content" >/dev/null 2>&1; then
                # Write content - jq -r converts \n to actual newlines
                echo "$CHANGES_JSON" | jq -r ".files[$i].content" > "$FILE_PATH"
                
                BYTES=$(wc -c < "$FILE_PATH" | tr -d ' ')
                LINES=$(wc -l < "$FILE_PATH" | tr -d ' ')
                echo "    Written $BYTES bytes, $LINES lines"
                ((APPLIED++)) || true
            else
                echo "    WARNING: No content found for this file" >&2
                ((ERRORS++)) || true
            fi
            ;;
        delete)
            if [[ -f "$FILE_PATH" ]]; then
                rm "$FILE_PATH"
                echo "    Deleted"
                ((APPLIED++)) || true
            else
                echo "    WARNING: File not found for deletion" >&2
            fi
            ;;
        *)
            echo "    WARNING: Unknown action '$ACTION'" >&2
            ((ERRORS++)) || true
            ;;
    esac
done

log_subsection "SUMMARY"
echo "Applied: $APPLIED"
echo "Errors: $ERRORS"

# Show git status
log_subsection "GIT STATUS"
git status --short

if [[ $APPLIED -gt 0 ]]; then
    echo ""
    echo "SUCCESS: $APPLIED file(s) changed"
    exit 0
else
    echo ""
    echo "WARNING: No files were changed"
    exit 0
fi
