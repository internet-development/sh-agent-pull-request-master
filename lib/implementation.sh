#!/bin/bash
#
# NOTE(angeldev)
# Implementation phase functions for the www-agent workflow.
# Handles Engineer implementation, code application, and commit generation.

[[ -n "${_IMPLEMENTATION_SH_LOADED:-}" ]] && return 0
_IMPLEMENTATION_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTERS_DIR="$(cd "$SCRIPT_DIR/../adapters" && pwd)"

# NOTE(angeldev)
# Global variable to store the JSON result from apply_code_changes.
# Contains detailed information about applied/failed edits including error messages and closest matches.
APPLY_RESULT_JSON=""

# NOTE(angeldev)
# Ensures the working repo is in a clean, up-to-date state.
# Call this before reading files or applying edits to avoid stale content issues.
refresh_working_repo() {
    if [[ -z "$TARGET_REPO_PATH" || ! -d "$TARGET_REPO_PATH" ]]; then
        return 1
    fi

    cd "$TARGET_REPO_PATH" || return 1

    # Fetch latest and reset to ensure clean state
    local default_branch
    default_branch=$(git remote show origin 2>/dev/null | grep "HEAD branch" | cut -d: -f2 | tr -d ' ')
    if [[ -z "$default_branch" ]]; then
        default_branch="main"
    fi

    # Only reset if we're on the default branch (not a feature branch)
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [[ "$current_branch" == "$default_branch" ]]; then
        git fetch origin --prune 2>/dev/null
        git reset --hard "origin/$default_branch" 2>/dev/null
        git clean -fd 2>/dev/null
    fi

    cd - > /dev/null || return 0
}

# NOTE(jimmylee)
# Reads existing file contents for files that need to be modified.
read_existing_files() {
    local file_paths="$1"

    if [[ -z "$TARGET_REPO_PATH" ]]; then
        echo ""
        return
    fi

    # Refresh repo to ensure we're reading current content
    refresh_working_repo 2>/dev/null
    
    if [[ -z "$file_paths" ]]; then
        echo ""
        return
    fi
    
    # Use Rust tool to read files with line numbers
    local files_output
    files_output=$("${ADAPTERS_DIR}/apply-edits.sh" read --files "$file_paths" --workdir "$TARGET_REPO_PATH" --max-lines "${MAX_FILE_LINES:-500}" --format json 2>/dev/null) || {
        # Fallback to legacy git-read-files if Rust tool not available
        files_output=$("${ADAPTERS_DIR}/git-read-files.sh" --workdir "$TARGET_REPO_PATH" --files "$file_paths" 2>/dev/null) || {
            echo ""
            return
        }
    }
    
    # Format as readable context
    local formatted=""
    local file_count
    file_count=$(echo "$files_output" | jq -r '.files | length' 2>/dev/null) || file_count=0
    
    if [[ "$file_count" -gt 0 ]]; then
        formatted="## Existing File Contents\n\n"
        formatted+="Below are the current contents of files you may need to modify.\n"
        formatted+="Line numbers are provided to help you reference specific locations.\n\n"
        
        for i in $(seq 0 $((file_count - 1))); do
            local path exists content content_with_lines lines truncated
            path=$(echo "$files_output" | jq -r ".files[$i].path")
            exists=$(echo "$files_output" | jq -r ".files[$i].exists")
            
            if [[ "$exists" == "true" ]]; then
                lines=$(echo "$files_output" | jq -r ".files[$i].lines // 0")
                truncated=$(echo "$files_output" | jq -r ".files[$i].truncated // false")
                
                # Prefer content_with_line_numbers if available (from Rust tool)
                content_with_lines=$(echo "$files_output" | jq -r ".files[$i].content_with_line_numbers // empty")
                if [[ -n "$content_with_lines" ]]; then
                    content="$content_with_lines"
                else
                    content=$(echo "$files_output" | jq -r ".files[$i].content // empty")
                fi
                
                local ext=""
                ext="${path##*.}"
                
                local truncated_note=""
                if [[ "$truncated" == "true" ]]; then
                    truncated_note=" (truncated)"
                fi
                
                formatted+="### ${path} (${lines} lines${truncated_note})\n\n"
                formatted+="\`\`\`${ext}\n${content}\n\`\`\`\n\n"
            else
                formatted+="### ${path}\n\n"
                formatted+="*File does not exist - will be created*\n\n"
            fi
        done
    fi
    
    echo -e "$formatted"
}

# NOTE(angeldev)
# Implements changes in chunks when there are many files to modify.
# This prevents context overflow and allows for better focus on each batch.
#
# Strategy:
# - If files_likely_affected > CHUNK_THRESHOLD (default 5), split into batches
# - Each batch focuses on related files (by directory or semantic grouping)
# - Results are combined and committed together
implement_changes_chunked() {
    local requirements_json="$1"
    local repo_context="$2"
    local persona_feedback="${3:-}"

    local chunk_threshold="${EDIT_CHUNK_THRESHOLD:-5}"
    local chunk_size="${EDIT_CHUNK_SIZE:-3}"

    # Extract files that might need modification
    local files_likely_affected
    files_likely_affected=$(echo "$requirements_json" | jq -r '.files_likely_affected // []' 2>/dev/null)

    local file_count
    file_count=$(echo "$files_likely_affected" | jq 'length' 2>/dev/null) || file_count=0

    # If few files, use normal implementation
    if [[ "$file_count" -le "$chunk_threshold" ]]; then
        implement_changes "$requirements_json" "$repo_context" "$persona_feedback"
        return $?
    fi

    log "CHUNK" "Large edit set detected ($file_count files), using chunked strategy"

    # Group files by directory
    local grouped_files
    grouped_files=$(echo "$files_likely_affected" | jq -r '
        group_by(. | split("/")[:-1] | join("/")) |
        map({dir: (.[0] | split("/")[:-1] | join("/")), files: .})
    ' 2>/dev/null)

    # Create chunks of related files
    local chunks=()
    local current_chunk=()
    local current_count=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        current_chunk+=("$file")
        ((current_count++))

        if [[ "$current_count" -ge "$chunk_size" ]]; then
            chunks+=("$(IFS=,; echo "${current_chunk[*]}")")
            current_chunk=()
            current_count=0
        fi
    done <<< "$(echo "$files_likely_affected" | jq -r '.[]' 2>/dev/null)"

    # Add remaining files as final chunk
    if [[ ${#current_chunk[@]} -gt 0 ]]; then
        chunks+=("$(IFS=,; echo "${current_chunk[*]}")")
    fi

    log "CHUNK" "Split into ${#chunks[@]} chunk(s)"

    # Process each chunk
    local all_edits="[]"
    local chunk_num=0

    for chunk_files in "${chunks[@]}"; do
        ((chunk_num++))
        log "CHUNK" "Processing chunk $chunk_num/${#chunks[@]}: $chunk_files"

        # Create modified requirements for this chunk
        local chunk_requirements
        chunk_requirements=$(echo "$requirements_json" | jq --arg files "$chunk_files" '
            .files_likely_affected = ($files | split(","))
        ' 2>/dev/null)

        # Implement this chunk
        request_spacing_with_progress 2000 "Engineer implementing chunk $chunk_num..."
        local chunk_response
        chunk_response=$(implement_changes "$chunk_requirements" "$repo_context" "$persona_feedback") || {
            log_warning "CHUNK" "Chunk $chunk_num failed, continuing with remaining chunks"
            continue
        }

        # Extract edits and accumulate
        local chunk_edits
        chunk_edits=$(extract_json "$chunk_response" | jq '.edits // []' 2>/dev/null) || chunk_edits="[]"

        all_edits=$(echo "$all_edits" | jq --argjson new "$chunk_edits" '. + $new' 2>/dev/null)

        log_success "CHUNK" "Chunk $chunk_num complete"
    done

    # Return combined edits
    local combined_response
    combined_response=$(jq -n --argjson edits "$all_edits" '{
        edits: $edits,
        commit_message: "feat: implement changes across multiple files",
        summary: "Changes implemented in chunks for better accuracy"
    }' 2>/dev/null)

    echo '```json'
    echo "$combined_response"
    echo '```'
}

# NOTE(jimmylee)
# Engineer implements based on synthesized requirements and persona feedback
implement_changes() {
    local requirements_json="$1"
    local repo_context="$2"
    local persona_feedback="${3:-}"

    # Extract files that might need modification
    local files_likely_affected
    files_likely_affected=$(echo "$requirements_json" | jq -r '.files_likely_affected // [] | join(",")' 2>/dev/null) || files_likely_affected=""

    # Read existing file contents if we know which files might be affected
    local existing_files_context=""
    if [[ -n "$files_likely_affected" ]]; then
        log "READ" "Reading existing files: $files_likely_affected" >&2
        existing_files_context=$(read_existing_files "$files_likely_affected")
    fi

    local prompt="## Implementation Requirements

${requirements_json}

## Target Repository: ${GITHUB_REPO_AGENTS_WILL_WORK_ON}

${repo_context}

## Current File Contents (READ CAREFULLY - THIS IS THE SOURCE OF TRUTH)

⚠️ CRITICAL: The file contents below are the ONLY valid source for your search/anchor strings.
- NEVER invent or assume content exists - only use what you can see below
- If a file is empty or doesn't have the content you expect, adjust your approach
- If you need to reference content, it MUST appear in the file contents shown here

${existing_files_context}"

    # Include persona feedback if provided
    if [[ -n "$persona_feedback" ]]; then
        prompt="${prompt}

## Feedback & Guidance

${persona_feedback}

IMPORTANT: Address these concerns and follow the guidance above."
    fi

    # Extract out_of_scope from requirements
    local out_of_scope
    out_of_scope=$(echo "$requirements_json" | jq -r '.out_of_scope // [] | join("\n- ")' 2>/dev/null) || out_of_scope=""

    prompt="${prompt}

## CRITICAL: Scope Restrictions

ONLY make changes that directly fulfill the requirements above.

### OUT OF SCOPE - DO NOT TOUCH:
- ${out_of_scope}
- Any file not listed in files_likely_affected unless absolutely necessary
- Formatting, whitespace, or style of existing code
- Adding unnecessary comments - only add comments when truly needed for clarity
- \"Improving\" or \"cleaning up\" existing code

### IF YOU MUST ADD CODE COMMENTS:
When adding comments to explain complex logic, use this format so the source is traceable:
- JavaScript/TypeScript: // NOTE(www-agent) Your comment here
- Python: # NOTE(www-agent) Your comment here
- CSS/SCSS: /* NOTE(www-agent) Your comment here */
- HTML: <!-- NOTE(www-agent) Your comment here -->
Do NOT add comments just to explain obvious code. Only comment truly complex or non-obvious logic.

### STRICT RULES:

1. **READ BEFORE WRITE**: Use the file contents with line numbers above - NEVER guess
2. **SURGICAL EDITS**: Use targeted edit operations, not full file replacement
3. **NO DRIVE-BY FIXES**: Don't fix unrelated issues you notice
4. **MATCH STYLE**: Copy EXACT formatting and patterns from existing code
5. **UNIQUE SEARCH STRINGS**: Include enough context (3-5 lines) to match exactly one location
6. **USE LINE NUMBERS**: Reference line numbers from the file contents when thinking about changes

## CRITICAL: Output Format - TARGETED EDITS

Output a JSON block with targeted edits (NOT full file content):

\`\`\`json
{
  \"edits\": [
    {
      \"path\": \"src/components/Header.tsx\",
      \"type\": \"insert_after\",
      \"anchor\": \"import { useState } from 'react';\",
      \"content\": \"import { useAuth } from '@/hooks/useAuth';\"
    },
    {
      \"path\": \"src/components/Header.tsx\",
      \"type\": \"replace\",
      \"search\": \"export function Header() {\\n  const [isOpen, setIsOpen] = useState(false);\\n  return (\",
      \"replace\": \"export function Header() {\\n  const [isOpen, setIsOpen] = useState(false);\\n  const { user } = useAuth();\\n  return (\"
    },
    {
      \"path\": \"src/components/NewFile.tsx\",
      \"type\": \"create\",
      \"content\": \"import React from 'react';\\n\\nexport function NewComponent() {\\n  return <div>New</div>;\\n}\"
    }
  ],
  \"commit_message\": \"feat(scope): description of change\",
  \"summary\": \"Brief description of what was implemented\"
}
\`\`\`

### Edit Types:
- \`replace\`: Replace first occurrence of 'search' with 'replace' (multi-line supported)
- \`replace_all\`: Replace ALL occurrences of 'search' with 'replace'
- \`insert_after\`: Insert 'content' after line containing 'anchor'
- \`insert_before\`: Insert 'content' before line containing 'anchor'
- \`create\`: Create new file with 'content'
- \`delete_file\`: Delete the file
- \`append\`: Append 'content' to end of file
- \`delete_match\`: Delete line(s) containing 'search'

### ⛔ ABSOLUTE RULE - READ THIS FIRST:
Your search/anchor strings MUST come from the \"Current File Contents\" section above.
- If you cannot find the text you want to modify in the file contents shown, DO NOT GUESS
- If a file appears empty or different than expected, work with what IS there
- NEVER assume comments like \"// NOTE(...)\" exist unless you can see them in the file
- When in doubt, use \`insert_at_line\` with a line number you can verify from the content above

### CRITICAL Rules for Search/Anchor Strings:
1. **ONLY USE VISIBLE CONTENT**: Your search string must appear verbatim in the file contents above
2. **INCLUDE ENOUGH CONTEXT**: Use 3-5 lines minimum to ensure uniqueness
3. **COPY EXACTLY**: Copy the EXACT text from the file contents INCLUDING ALL WHITESPACE
4. **COUNT THE SPACES**: Look at the line numbers and count the exact indentation (spaces/tabs)
5. **MULTI-LINE IS BETTER**: Multi-line search strings are more unique and reliable
6. **VERIFY UNIQUENESS**: Check the line numbers - your search string should only match once
7. **INCLUDE SURROUNDING CODE**: Not just the line you want to change, but lines before/after too

### ⚠️ MANDATORY COPY-PASTE INSTRUCTION:
For search strings, COPY-PASTE directly from the file contents above.
Do NOT retype the code. Select the exact lines shown and paste them.
The tool will attempt to auto-correct minor indentation differences, but exact matches are always preferred.

### INDENTATION CHECK (Do This Before Every Edit):
Before outputting each search string, verify:
1. Count leading spaces in your search string
2. Count leading spaces in the file (shown with line numbers above)
3. These numbers MUST match exactly

Example verification:
  File line 45:     \"            if (user) {\"   <- Count: 12 spaces
  Your search:      \"            if (user) {\"   <- Must also be 12 spaces

### LINE-NUMBER FALLBACK:
IF UNSURE about exact match, use insert_at_line with the line number shown:
  {\"type\": \"insert_at_line\", \"path\": \"file.ts\", \"line\": 45, \"content\": \"new code\"}
This is MORE RELIABLE than search-based edits when context is complex.

### BAD vs GOOD Examples (With Character Counts):

❌ BAD (8 spaces - wrong):
   \"search\": \"        if (user) {\"

✅ GOOD (12 spaces - matches file):
   \"search\": \"            if (user) {\"

Count the dots: ............if (user) {  <- 12 spaces

❌ BAD (too short, might match multiple places):
   \"search\": \"return null;\"

✅ GOOD (includes unique context with correct indentation):
   \"search\": \"    if (!user) {\\n      return null;\\n    }\"

### UNIQUENESS VERIFICATION:
BEFORE OUTPUT: For each search string, mentally verify:
- Does this appear exactly ONCE in the file? (check line numbers)
- If it appears multiple times, include MORE CONTEXT (3-5 lines)
- If still not unique, use insert_at_line instead

### Other Rules:
1. For 'create': provide FULL file content
2. Commit message format: type(scope): description (feat, fix, docs, etc.)
3. Output ONLY the JSON block - no explanations before or after

## Task

Implement the requirements using targeted edits. Be surgical and precise."

    invoke_persona "engineer" "$prompt"
}

# NOTE(angeldev)
# Applies code changes from Engineer's JSON output to actual files.
apply_code_changes() {
    local engineer_response="$1"
    
    # Reset global result variable
    APPLY_RESULT_JSON=""

    if [[ -z "$TARGET_REPO_PATH" ]]; then
        log_error "APPLY" "Target repo path not set"
        return 1
    fi

    # Extract JSON from markdown code block if present
    local changes_json
    changes_json=$(extract_json "$engineer_response")

    # Validate JSON before proceeding
    if ! echo "$changes_json" | jq empty 2>/dev/null; then
        log_error "APPLY" "Failed to parse Engineer's JSON output"
        log_error "APPLY" "Response preview: ${engineer_response:0:500}"
        return 1
    fi
    
    # Normalize JSON format for various LLM outputs
    changes_json=$(echo "$changes_json" | jq '
        if .files then
            if [.files[].action] | map(select(. != null)) | map(. as $a | ["create", "modify", "delete"] | index($a) | not) | any then
                {
                    edits: [.files[] | 
                        if .action == "insert" then
                            if .insert_location then
                                { path: .path, type: "insert_at_line", line: .insert_location, content: .content }
                            else
                                { path: .path, type: "create", content: .content }
                            end
                        elif .action == "replace" then
                            if .search then
                                { path: .path, type: "replace", search: .search, replace: .content }
                            elif .original then
                                { path: .path, type: "replace", search: .original, replace: .content }
                            else
                                { path: .path, type: "_skipped", _reason: "replace without search" }
                            end
                        elif .action == "create" or .action == "modify" then
                            { path: .path, type: "create", content: .content }
                        elif .action == "delete" then
                            { path: .path, type: "delete_file" }
                        else
                            { path: .path, type: "create", content: .content }
                        end
                    ] | map(select(.type != "_skipped")),
                    summary: (.summary // "Changes applied"),
                    commit_message: (.commit_message // null)
                }
            else
                .
            end
        elif .edits then
            .edits = [.edits[] |
                (if .operation then .type = .operation | del(.operation) else . end) |
                (if .file then .path = .file | del(.file) else . end) |
                (if .type then .type = (.type | gsub("-"; "_")) else . end) |
                (if .target then
                    if .type == "replace" or .type == "replace_all" or .type == "delete_match" then
                        .search = .target | del(.target)
                    elif .type == "insert_after" or .type == "insert_before" then
                        .anchor = .target | del(.target)
                    else . end
                else . end) |
                (if (.type == "insert_after" or .type == "insert_before") and .search and (.anchor | not) then
                    .anchor = .search | del(.search)
                else . end) |
                # NOTE(angeldev): Fix common mistake of using "replace" instead of "content" for insert operations
                (if (.type == "insert_after" or .type == "insert_before" or .type == "create" or .type == "append") and .replace and (.content | not) then
                    .content = .replace | del(.replace)
                else . end)
            ]
        else .
        end
    ' 2>/dev/null) || {
        log_warning "APPLY" "JSON normalization failed, using original"
    }

    # Write JSON to temp file to avoid argument length limits
    local temp_json_file
    temp_json_file=$(make_temp_file "changes_json")
    echo "$changes_json" > "$temp_json_file"

    log "APPLY" "Wrote JSON to temp file: $temp_json_file"
    log "APPLY" "JSON size: $(wc -c < "$temp_json_file" | tr -d ' ') bytes"

    # Detect format and use appropriate applier
    local has_edits
    has_edits=$(echo "$changes_json" | jq 'has("edits")' 2>/dev/null)

    # Validate edit structure before calling Rust tool
    if [[ "$has_edits" == "true" ]]; then
        local validation_errors
        validation_errors=$(echo "$changes_json" | jq -r '
            [.edits | to_entries[] |
                .key as $idx |
                .value |
                if .type == null then
                    "Edit \($idx): missing required field \"type\""
                elif .path == null then
                    "Edit \($idx): missing required field \"path\""
                elif (.type == "insert_after" or .type == "insert_before") and .anchor == null then
                    "Edit \($idx) (\(.type)): missing required field \"anchor\""
                elif (.type == "replace" or .type == "replace_all") and .search == null then
                    "Edit \($idx) (\(.type)): missing required field \"search\""
                elif (.type == "replace" or .type == "replace_all") and .replace == null then
                    "Edit \($idx) (\(.type)): missing required field \"replace\""
                elif (.type == "insert_after" or .type == "insert_before" or .type == "create" or .type == "append" or .type == "prepend") and .content == null then
                    "Edit \($idx) (\(.type)): missing required field \"content\""
                else
                    empty
                end
            ] | join("\n")
        ' 2>/dev/null)

        if [[ -n "$validation_errors" ]]; then
            log_error "VALIDATION" "Edit structure errors detected:"
            echo "$validation_errors" | while IFS= read -r err; do
                log_error "VALIDATION" "  $err"
            done
            log_error "VALIDATION" "Will attempt to apply anyway - Rust tool may provide more details"
        fi
    fi

    local apply_output
    local apply_json=""
    local human_output=""

    if [[ "$has_edits" == "true" ]]; then
        log "APPLY" "Using Rust edit-based applier"
        
        local temp_stdout temp_stderr
        temp_stdout=$(make_temp_file "apply_stdout")
        temp_stderr=$(make_temp_file "apply_stderr")
        
        "${ADAPTERS_DIR}/apply-edits.sh" --file "$temp_json_file" --workdir "$TARGET_REPO_PATH" \
            >"$temp_stdout" 2>"$temp_stderr" || true
        
        apply_json=$(cat "$temp_stdout")
        human_output=$(cat "$temp_stderr")
        apply_output="$human_output"
        
        if [[ -n "$human_output" ]]; then
            echo "$human_output" >&2
        fi
        
        local success applied failed
        success=$(echo "$apply_json" | jq -r '.success // true' 2>/dev/null)
        applied=$(echo "$apply_json" | jq -r '.applied // 0' 2>/dev/null)
        failed=$(echo "$apply_json" | jq -r '.failed // 0' 2>/dev/null)
        
        APPLY_RESULT_JSON="$apply_json"
        
        if [[ "$success" == "false" || "$failed" -gt 0 ]]; then
            log_warning "APPLY" "Some edits failed: $applied applied, $failed failed"
            
            local errors
            errors=$(echo "$apply_json" | jq -r '.edits[] | select(.status == "error") | "\(.path): \(.message)"' 2>/dev/null)
            if [[ -n "$errors" ]]; then
                log_warning "ERRORS" "$errors"
            fi
        else
            log_success "APPLY" "All edits applied successfully: $applied edit(s)"
        fi
        
        rm -f "$temp_stdout" "$temp_stderr"
    else
        log "APPLY" "Using full-file applier (legacy format)"
        apply_output=$("${ADAPTERS_DIR}/apply-file-changes.sh" --file "$temp_json_file" --workdir "$TARGET_REPO_PATH" 2>&1) || {
            log_warning "APPLY" "Some changes may have failed"
        }
    fi

    rm -f "$temp_json_file"
    echo "$apply_output"
}

# NOTE(angeldev)
# Retry failed edits by feeding error details back to the Engineer.
retry_failed_edits() {
    local apply_result_json="$1"
    local original_engineer_response="$2"
    
    local failed_edits
    failed_edits=$(echo "$apply_result_json" | jq '[.edits[] | select(.status == "error")]' 2>/dev/null)
    
    local failed_count
    failed_count=$(echo "$failed_edits" | jq 'length' 2>/dev/null)
    
    if [[ "$failed_count" == "0" || -z "$failed_count" ]]; then
        log "RETRY" "No failed edits to retry"
        return 0
    fi
    
    log "RETRY" "Preparing to retry $failed_count failed edit(s)..."
    
    local original_json
    original_json=$(extract_json "$original_engineer_response")
    
    local failed_paths
    failed_paths=$(echo "$failed_edits" | jq -r '.[].path' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    
    local files_context=""
    if [[ -n "$failed_paths" ]]; then
        log "READ" "Reading files for retry context: $failed_paths" >&2
        files_context=$(read_existing_files "$failed_paths")
    fi
    
    local error_details=""
    error_details=$(echo "$failed_edits" | jq -r '
        .[] | 
        "### Failed Edit #\(.index + 1): \(.path)\n" +
        "**Type:** \(.type)\n" +
        "**Error:** \(.error) - \(.message)\n" +
        (if .search_preview then "**Your search string:**\n```\n\(.search_preview)\n```\n" else "" end) +
        (if .hint then "**Hint:** \(.hint)\n" else "" end) +
        (if .closest_matches and (.closest_matches | length) > 0 then 
            "**Closest matches found in file:**\n" + 
            (.closest_matches | to_entries | map(
                "Match \(.key + 1) (line \(.value.line), \((.value.similarity * 100 | floor))% similar):\n```\n\(.value.content)\n```"
            ) | join("\n\n"))
        else "" end) +
        "\n---\n"
    ' 2>/dev/null)
    
    local prompt="## Retry Failed Edits

Your previous implementation had ${failed_count} edit(s) that failed to apply.

⚠️ CRITICAL: ATOMIC ROLLBACK OCCURRED
Because edits failed, ALL changes have been ROLLED BACK. The files are back to their ORIGINAL state.
- Any content you tried to add (like comments, new code) does NOT exist in the files
- Do NOT search for content you were trying to add - it was never written
- The \"Current File Contents\" below shows the ACTUAL current state

## Error Details

${error_details}

## Current File Contents (ACTUAL STATE - your changes were rolled back)

${files_context}

## Rules for Fixing

1. **FORGET YOUR PREVIOUS CHANGES**: They were rolled back and do not exist
2. **ONLY USE CONTENT SHOWN ABOVE**: The file contents above are the ONLY truth
3. **USE THE CLOSEST MATCHES**: Look at the \"Closest matches\" above - copy that EXACT text
4. **COPY EXACTLY**: Include the exact indentation, spacing, and characters from the file
5. **USE MORE CONTEXT**: Include 3-5 lines to make the search string unique
6. **CHECK LINE NUMBERS**: Reference the line numbers above to find the exact location

## Output Format

Output ONLY the corrected edits for the failed operations:

\`\`\`json
{
  \"edits\": [
    {
      \"path\": \"path/to/file.ts\",
      \"type\": \"replace\",
      \"search\": \"EXACT text copied from closest match or file contents above\",
      \"replace\": \"your replacement text\"
    }
  ],
  \"summary\": \"Corrected search strings to match actual file contents\"
}
\`\`\`

### Edit Types and Required Fields:
- \`replace\`/\`replace_all\`: Requires \"search\" and \"replace\"
- \`insert_after\`/\`insert_before\`: Requires \"anchor\" and \"content\" (NOT \"replace\"!)
- \`create\`/\`append\`: Requires \"content\"
- \`delete_match\`: Requires \"search\"

Output ONLY the JSON block for the failed edits - do not re-output edits that already succeeded."

    invoke_persona "engineer" "$prompt"
}

# NOTE(angeldev)
# Apply edits with automatic retry for failures.
apply_code_changes_with_retry() {
    local engineer_response="$1"
    local max_retry_attempts="${2:-${MAX_APPLY_RETRIES:-2}}"
    
    local attempt=1
    local all_succeeded=false
    local current_response="$engineer_response"
    
    while [[ $attempt -le $((max_retry_attempts + 1)) && "$all_succeeded" != "true" ]]; do
        if [[ $attempt -gt 1 ]]; then
            log "RETRY" "Edit retry attempt $((attempt - 1))/$max_retry_attempts..."
            request_spacing_with_progress 2000 "Engineer fixing failed edits..."
        fi
        
        local apply_output
        apply_output=$(apply_code_changes "$current_response")
        
        if [[ -z "$APPLY_RESULT_JSON" ]]; then
            log "APPLY" "No detailed result available (legacy format)"
            all_succeeded=true
            break
        fi
        
        local failed_count
        failed_count=$(echo "$APPLY_RESULT_JSON" | jq -r '.failed // 0' 2>/dev/null)
        
        if [[ "$failed_count" == "0" ]]; then
            all_succeeded=true
            break
        fi
        
        if [[ $attempt -gt $max_retry_attempts ]]; then
            log_warning "RETRY" "Some edits still failing after $max_retry_attempts retry attempts"
            break
        fi
        
        local retry_response
        retry_response=$(retry_failed_edits "$APPLY_RESULT_JSON" "$current_response") || {
            log_warning "RETRY" "Failed to get retry response from Engineer"
            break
        }
        
        local retry_json
        retry_json=$(extract_json "$retry_response")
        
        if ! echo "$retry_json" | jq -e '.edits' >/dev/null 2>&1; then
            log_warning "RETRY" "Engineer retry response missing edits array"
            break
        fi
        
        current_response="$retry_response"
        ((attempt++))
    done
    
    if [[ "$all_succeeded" == "true" ]]; then
        return 0
    else
        local applied_count
        applied_count=$(echo "$APPLY_RESULT_JSON" | jq -r '.applied // 0' 2>/dev/null)
        if [[ "$applied_count" -gt 0 ]]; then
            log_warning "APPLY" "Partial success: $applied_count edit(s) applied, some failed"
            return 0
        fi
        return 1
    fi
}

# NOTE(jimmylee)
# Generates a conventional commit message based on changes.
generate_commit_message() {
    local change_type="$1"
    local scope="$2"
    local description="$3"
    local body="${4:-}"
    local breaking="${5:-}"
    
    local message=""
    
    if [[ -n "$scope" ]]; then
        message="${change_type}(${scope}): ${description}"
    else
        message="${change_type}: ${description}"
    fi
    
    message=$(echo "$message" | cut -c1-72)
    
    if [[ -n "$body" ]]; then
        message="${message}

${body}"
    fi
    
    if [[ -n "$breaking" ]]; then
        message="${message}

BREAKING CHANGE: ${breaking}"
    fi
    
    echo "$message"
}

# NOTE(jimmylee)
# Asks a persona to determine the commit type and scope from changes.
determine_commit_info() {
    local changes_summary="$1"
    local directive="$2"

    local git_diff=""
    if [[ -n "${TARGET_REPO_PATH:-}" && -d "$TARGET_REPO_PATH" ]]; then
        git_diff=$(cd "$TARGET_REPO_PATH" && git diff --cached --stat 2>/dev/null || git diff --stat 2>/dev/null || echo "")
        if [[ -n "$git_diff" ]]; then
            git_diff="

## Files Changed (git diff --stat)
\`\`\`
${git_diff}
\`\`\`"
        fi
    fi

    local prompt="Analyze these changes and create a COMPLETE, HOLISTIC commit message that tells the story of this change.

## Original Directive (the WHY)
${directive}

## Changes Made
${changes_summary}
${git_diff}

## Your Task
Create a commit message that:
1. **Connects to the requirement** - Why was this change needed?
2. **Explains the approach** - What solution was chosen and why?
3. **Notes relationships** - If multiple files changed, how do they relate?
4. **Flags non-obvious decisions** - Any trade-offs or alternatives considered?

Output JSON:

\`\`\`json
{
  \"type\": \"feat|fix|docs|style|refactor|perf|test|chore\",
  \"scope\": \"component-name or empty string\",
  \"description\": \"imperative description under 50 chars\",
  \"body\": \"Multi-line explanation of WHY this change was made.\\nConnect it to the original requirement.\\nExplain any non-obvious decisions.\",
  \"breaking\": \"only if backwards-incompatible, otherwise empty\"
}
\`\`\`

## Guidelines

**Type Selection:**
- feat: New feature or capability for users
- fix: Bug fix (something was broken, now it works)
- refactor: Code restructuring without behavior change
- perf: Performance improvement
- docs: Documentation only
- style: Formatting, whitespace, no code change
- test: Adding or fixing tests
- chore: Maintenance, dependencies, tooling

**Description:** Imperative mood, lowercase, no period (e.g., 'add logout button to header')

**Body (CRITICAL):**
- Explain the reasoning, NOT what the diff shows
- Connect to the user requirement or problem
- If multiple files: explain how they work together
- Keep it concise but complete (2-4 lines typical)"

    invoke_persona "project-manager" "$prompt"
}

# NOTE(jimmylee)
# Validates that Engineer's JSON output is well-formed and has required fields
validate_engineer_output() {
    local json_content="$1"

    if ! echo "$json_content" | jq empty 2>/dev/null; then
        log_error "VALIDATE" "Invalid JSON from Engineer"
        return 1
    fi

    local has_edits has_files
    has_edits=$(echo "$json_content" | jq 'has("edits")' 2>/dev/null)
    has_files=$(echo "$json_content" | jq 'has("files")' 2>/dev/null)

    if [[ "$has_edits" == "true" ]]; then
        local edits_count
        edits_count=$(echo "$json_content" | jq -r '.edits | length // 0' 2>/dev/null)
        if [[ "$edits_count" == "0" || "$edits_count" == "null" ]]; then
            log_error "VALIDATE" "No edits in Engineer's output"
            return 1
        fi
        log "VALIDATE" "Valid edit-based output with $edits_count edit(s)"
        return 0
    elif [[ "$has_files" == "true" ]]; then
        local files_count
        files_count=$(echo "$json_content" | jq -r '.files | length // 0' 2>/dev/null)
        if [[ "$files_count" == "0" || "$files_count" == "null" ]]; then
            log_error "VALIDATE" "No files in Engineer's output"
            return 1
        fi
        
        for i in $(seq 0 $((files_count - 1))); do
            local path action
            path=$(echo "$json_content" | jq -r ".files[$i].path // empty")
            action=$(echo "$json_content" | jq -r ".files[$i].action // empty")

            if [[ -z "$path" ]]; then
                log_error "VALIDATE" "File at index $i missing path"
                return 1
            fi

            if [[ "$action" != "delete" ]]; then
                if ! echo "$json_content" | jq -e ".files[$i].content" >/dev/null 2>&1; then
                    log_error "VALIDATE" "File $path missing content"
                    return 1
                fi
            fi
        done

        log_success "VALIDATE" "Engineer output valid (legacy): $files_count file(s)"
        return 0
    else
        log_error "VALIDATE" "Engineer output has neither 'edits' nor 'files' array"
        return 1
    fi
}

# NOTE(jimmylee)
# Asks Engineer to fix malformed JSON output
fix_malformed_output() {
    local original_response="$1"
    local error_message="$2"
    
    local prompt="## Your Previous Output Had Errors

Error: ${error_message}

Your previous response:
\`\`\`
${original_response:0:2000}
\`\`\`

## Fix Required

Your output must be valid JSON with this structure:

\`\`\`json
{
  \"files\": [
    {
      \"path\": \"relative/path/to/file.js\",
      \"action\": \"create\",
      \"content\": \"file content with \\n for newlines\"
    }
  ],
  \"summary\": \"What was changed\"
}
\`\`\`

Please output the corrected JSON now. Only output the JSON block, nothing else."

    invoke_persona "engineer" "$prompt"
}
