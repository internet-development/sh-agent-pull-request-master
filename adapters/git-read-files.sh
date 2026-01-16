#!/bin/bash
# Adapter: Read file contents from the target repository
#
# Usage: ./git-read-files.sh --workdir <path> [--files "file1.js,file2.js"] [--pattern "*.tsx"]
#
# Arguments:
#   --workdir - Working directory (the cloned target repo) - REQUIRED
#   --files - Comma-separated list of specific files to read
#   --pattern - Glob pattern to match files (e.g., "*.tsx", "components/*.js")
#   --max-files - Maximum number of files to read (default: 10)
#   --max-lines - Maximum lines per file to include (default: 500)
#
# Output: JSON with file contents
# {
#   "files": [
#     {
#       "path": "relative/path/to/file.js",
#       "exists": true,
#       "content": "file content here",
#       "lines": 42,
#       "bytes": 1234
#     }
#   ]
# }

set -euo pipefail

WORKDIR=""
FILES=""
PATTERN=""
MAX_FILES=10
MAX_LINES=500

# NOTE(jimmylee)
# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        --files)
            FILES="$2"
            shift 2
            ;;
        --pattern)
            PATTERN="$2"
            shift 2
            ;;
        --max-files)
            MAX_FILES="$2"
            shift 2
            ;;
        --max-lines)
            MAX_LINES="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# NOTE(jimmylee)
# Validate workdir
if [[ -z "$WORKDIR" ]]; then
    echo "ERROR: --workdir is required" >&2
    exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
    echo "ERROR: Working directory does not exist: $WORKDIR" >&2
    exit 1
fi

cd "$WORKDIR"

# NOTE(jimmylee)
# Build list of files to read
FILE_LIST=()

# NOTE(jimmylee)
# Add specific files if provided
if [[ -n "$FILES" ]]; then
    IFS=',' read -ra ADDR <<< "$FILES"
    for file in "${ADDR[@]}"; do
        # Trim whitespace
        file=$(echo "$file" | xargs)
        if [[ -n "$file" ]]; then
            FILE_LIST+=("$file")
        fi
    done
fi

# NOTE(jimmylee)
# Add files matching pattern if provided
if [[ -n "$PATTERN" ]]; then
    while IFS= read -r -d '' file; do
        FILE_LIST+=("$file")
    done < <(find . -type f -name "$PATTERN" -not -path '*/\.*' -not -path '*/node_modules/*' -print0 2>/dev/null | head -z -n "$MAX_FILES")
fi

# NOTE(jimmylee)
# If no files specified, error out
if [[ ${#FILE_LIST[@]} -eq 0 ]]; then
    echo "ERROR: No files specified. Use --files or --pattern" >&2
    exit 1
fi

# NOTE(jimmylee)
# Limit number of files
if [[ ${#FILE_LIST[@]} -gt $MAX_FILES ]]; then
    FILE_LIST=("${FILE_LIST[@]:0:$MAX_FILES}")
fi

# NOTE(jimmylee)
# Start JSON output
echo '{"files": ['

first=true
for file_path in "${FILE_LIST[@]}"; do
    # Remove leading ./ if present
    file_path="${file_path#./}"
    
    if [[ "$first" != "true" ]]; then
        echo ","
    fi
    first=false
    
    if [[ -f "$file_path" ]]; then
        # File exists - read content
        local_content=$(head -n "$MAX_LINES" "$file_path" 2>/dev/null || echo "")
        local_lines=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ' || echo "0")
        local_bytes=$(wc -c < "$file_path" 2>/dev/null | tr -d ' ' || echo "0")
        local_truncated="false"
        
        if [[ "$local_lines" -gt "$MAX_LINES" ]]; then
            local_truncated="true"
        fi
        
        # Use jq to properly escape content for JSON
        jq -n \
            --arg path "$file_path" \
            --arg content "$local_content" \
            --argjson lines "$local_lines" \
            --argjson bytes "$local_bytes" \
            --argjson truncated "$local_truncated" \
            '{
                path: $path,
                exists: true,
                content: $content,
                lines: $lines,
                bytes: $bytes,
                truncated: $truncated
            }'
    else
        # File doesn't exist
        jq -n \
            --arg path "$file_path" \
            '{
                path: $path,
                exists: false,
                content: null,
                lines: 0,
                bytes: 0,
                truncated: false
            }'
    fi
done

echo ']}'
