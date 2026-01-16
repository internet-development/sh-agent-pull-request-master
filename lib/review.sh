#!/bin/bash
#
# NOTE(angeldev)
# Review phase functions for the www-agent workflow.
# Handles persona reviews, feedback synthesis, and fix iterations.

[[ -n "${_REVIEW_SH_LOADED:-}" ]] && return 0
_REVIEW_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTERS_DIR="$(cd "$SCRIPT_DIR/../adapters" && pwd)"

# NOTE(jimmylee)
# Get a review from a specific persona - returns JSON with structured feedback
get_persona_review() {
    local persona_name="$1"
    local pr_number="$2"
    local pr_diff="$3"
    local acceptance_criteria="$4"
    local cycle_number="${5:-1}"

    local review_focus=""
    case "$persona_name" in
        project-manager)
            review_focus="Focus on: Does this meet the acceptance criteria exactly? Is scope appropriate? Any missing requirements?"
            ;;
        technical-writer)
            review_focus="Focus on: Are naming conventions consistent with existing codebase? Is terminology aligned? Are error messages clear?"
            ;;
        researcher)
            review_focus="Focus on: Are best practices followed? Any security concerns? Performance issues? Is the approach sound?"
            ;;
        director)
            review_focus="Focus on: Overall quality, integration, and final approval. Synthesize any issues from other reviews."
            ;;
        *)
            review_focus="Provide your expert review based on your role."
            ;;
    esac

    local prompt="## Pull Request #${pr_number} - Code Review (Cycle ${cycle_number})

## Changes (Diff)

\`\`\`diff
${pr_diff}
\`\`\`

## Acceptance Criteria

${acceptance_criteria}

## Review Focus

${review_focus}

## Task

Review the code changes and output your review as a JSON block.

Your JSON MUST include a \`next_cycle_prompt\` field if decision is NEEDS_WORK.
This field contains PRECISE, ACTIONABLE instructions for the Engineer to fix the issues.

Example output:
\`\`\`json
{
  \"decision\": \"NEEDS_WORK\",
  \"summary\": \"One sentence overview\",
  \"issues\": [
    {
      \"severity\": \"critical\",
      \"file\": \"src/auth.ts\",
      \"line\": 45,
      \"problem\": \"Description of what's wrong\",
      \"fix\": \"Specific instruction to fix it\"
    }
  ],
  \"whats_good\": [\"Positive observations\"],
  \"next_cycle_prompt\": \"In src/auth.ts: (1) Line 45: add input validation for email field. (2) Line 67: rename 'data' to 'userData' for consistency with codebase pattern.\"
}
\`\`\`

Rules:
- decision: APPROVE | NEEDS_WORK | COMMENT
- Only mark NEEDS_WORK for real problems, not preferences
- next_cycle_prompt must be precise: file paths, line numbers, exact changes
- Comments using \`NOTE(www-agent)\` format are ALWAYS acceptable regardless of codebase conventions
- Output ONLY the JSON block"

    invoke_persona "$persona_name" "$prompt"
}

# NOTE(jimmylee)
# Parse decision from natural language review response
parse_review_decision() {
    local review_text="$1"
    
    if echo "$review_text" | grep -qiE '\*\*Decision\*\*:\s*(APPROVE|approve)'; then
        echo "APPROVE"
    elif echo "$review_text" | grep -qiE '\*\*Decision\*\*:\s*(NEEDS_WORK|needs_work|needs work)'; then
        echo "NEEDS_WORK"
    elif echo "$review_text" | grep -qiE 'NEEDS_WORK|needs work|changes required|must be fixed'; then
        echo "NEEDS_WORK"
    elif echo "$review_text" | grep -qiE 'LGTM|looks good|approved|APPROVE'; then
        echo "APPROVE"
    else
        echo "COMMENT"
    fi
}

# NOTE(jimmylee)
# Parse summary from natural language review response
parse_review_summary() {
    local review_text="$1"
    
    local summary
    summary=$(echo "$review_text" | grep -iE '^\*\*Summary\*\*:' | sed 's/^\*\*Summary\*\*:\s*//' | head -1)
    
    if [[ -z "$summary" ]]; then
        summary=$(echo "$review_text" | grep -A1 -iE '^\*\*Decision\*\*:' | tail -1 | sed 's/^\*\*//' | cut -c1-100)
    fi
    
    if [[ -z "$summary" ]]; then
        summary="Review provided"
    fi
    
    echo "$summary"
}

# NOTE(jimmylee)
# Engineer fixes issues based on synthesized review feedback
fix_review_issues() {
    local synthesized_prompt="$1"
    local repo_context="$2"
    local cycle_number="${3:-2}"

    local mentioned_files
    mentioned_files=$(echo "$synthesized_prompt" | grep -oE '[a-zA-Z0-9_/-]+\.(tsx?|jsx?|css|scss|json|md)' | sort -u | tr '\n' ',' | sed 's/,$//')

    local existing_files_context=""
    if [[ -n "$mentioned_files" ]]; then
        log "READ" "Reading files mentioned in feedback: $mentioned_files" >&2
        existing_files_context=$(read_existing_files "$mentioned_files")
    fi

    local prompt="## Fix Cycle ${cycle_number} - Address Review Feedback

⚠️ IMPORTANT: If previous edits failed, they were ROLLED BACK.
- The file contents below show the ACTUAL current state
- Do NOT reference any changes you tried to make previously - they may not exist
- ONLY use content that appears in the \"Current File Contents\" section below

## Synthesized Fix Instructions (from Director)

${synthesized_prompt}

## Current File Contents (THIS IS THE ACTUAL STATE - READ CAREFULLY)

${existing_files_context}

## Repository Context

${repo_context}

## Task

Follow the fix instructions above EXACTLY. Each item tells you:
- The file and line number
- What's wrong
- How to fix it

## Rules

1. **ONLY USE VISIBLE CONTENT**: Your search/anchor strings MUST appear in the file contents above
2. **NEVER REFERENCE PREVIOUS ATTEMPTS**: If your earlier edits failed, they don't exist - start fresh
3. **READ FILES FIRST**: Use the file contents with line numbers above - NEVER guess or assume
4. **FOLLOW INSTRUCTIONS PRECISELY**: Do exactly what's requested, nothing more
5. **SURGICAL EDITS**: Use targeted edit operations with multi-line search strings
6. **NO EXTRA CHANGES**: Don't fix other things you notice
7. **UNIQUE SEARCH STRINGS**: Include 3-5 lines of context to ensure uniqueness

## CRITICAL: Search String Rules

Your search strings MUST:
- Include enough surrounding context (3-5 lines) to be unique in the file
- Copy the EXACT text from the file contents, INCLUDING ALL WHITESPACE AND INDENTATION
- Count the leading spaces carefully (e.g., 16 spaces, not 14 or 12)
- Use multi-line strings for reliability

## Output Format - TARGETED EDITS

\`\`\`json
{
  \"edits\": [
    {
      \"path\": \"src/auth.ts\",
      \"type\": \"replace\",
      \"search\": \"  const d = new Date()\\n  const token = generateToken()\",
      \"replace\": \"  const tokenExpiry = new Date()\\n  const token = generateToken()\"
    },
    {
      \"path\": \"src/styles.css\",
      \"type\": \"insert_after\",
      \"anchor\": \".existing-class {\",
      \"content\": \".new-class {\\n  color: red;\\n}\"
    },
    {
      \"path\": \"src/new-file.ts\",
      \"type\": \"create\",
      \"content\": \"export const newFunction = () => {};\"
    }
  ],
  \"commit_message\": \"fix(scope): address review feedback\",
  \"summary\": \"Fixed: renamed variable, improved error message\",
  \"issues_addressed\": [\"tokenExpiry naming\", \"error message clarity\"]
}
\`\`\`

### Edit Types and Required Fields:
- \`replace\`: Requires \"search\" and \"replace\" - replaces first match
- \`replace_all\`: Requires \"search\" and \"replace\" - replaces ALL matches
- \`insert_after\`: Requires \"anchor\" and \"content\" - inserts content AFTER the anchor line
- \`insert_before\": Requires \"anchor\" and \"content\" - inserts content BEFORE the anchor line
- \`create\`: Requires \"content\" - creates a new file
- \`append\`: Requires \"content\" - appends to end of file
- \`delete_file\`: No extra fields - deletes the file
- \`delete_match\`: Requires \"search\" - deletes lines containing search

CRITICAL: Match the field names to the edit type! Do NOT use \"replace\" with \"insert_after\" - use \"content\" instead.

Output ONLY the JSON block - no explanations before or after."

    invoke_persona "engineer" "$prompt"
}

# NOTE(angeldev)
# Synthesize feedback from a SINGLE persona into a focused prompt for the Engineer.
synthesize_single_persona_feedback() {
    local persona_name="$1"
    local persona_review="$2"
    local cycle_number="$3"
    local attempt_number="${4:-1}"
    
    local review_json
    review_json=$(extract_json "$persona_review")
    
    local decision
    decision=$(echo "$review_json" | jq -r '.decision // "COMMENT"' 2>/dev/null)
    
    if [[ "$decision" == "APPROVE" ]]; then
        echo "APPROVE"
        return 0
    fi
    
    local prompt="## Synthesize Review Feedback - Cycle ${cycle_number}, Attempt ${attempt_number}

A review has identified issues that need to be addressed. Create a clear, actionable prompt for the Engineer.

## Review Findings
Decision: ${decision}

${persona_review}

## Task

Create a focused, prioritized fix prompt for the Engineer.

Output as JSON:

\`\`\`json
{
  \"decision\": \"NEEDS_WORK\",
  \"prioritized_next_cycle_prompt\": \"## Issues to Address\\n\\n1. [Most important issue with file:line and exact fix needed]\\n2. [Next issue...]\\n\\n## Context\\n- Make surgical, targeted edits\\n- Focus on the specific issues identified\"
}
\`\`\`

Rules:
1. Be SPECIFIC: Include exact file paths, line numbers, and what to change
2. Prioritize by impact: Fix the most important issues first
3. Be actionable: Each item should be something the Engineer can directly fix
4. Do NOT mention any role names (Project Manager, Technical Writer, etc.) - just describe the issues
5. Output ONLY the JSON block"

    invoke_persona "director" "$prompt"
}

# NOTE(angeldev)
# Process a single persona's review cycle with up to max_attempts fix iterations.
process_persona_review_cycle() {
    local persona_name="$1"
    local pr_number="$2"
    local acceptance_criteria="$3"
    local full_context="$4"
    local cycle_number="$5"
    local max_attempts="${6:-${MAX_FIX_ATTEMPTS_PER_PERSONA:-2}}"
    local previous_comments="${7:-}"
    
    local attempt=0
    local decision="NEEDS_WORK"
    
    local persona_display persona_full_name
    case "$persona_name" in
        project-manager) 
            persona_display="PM"
            persona_full_name="Project Manager"
            ;;
        technical-writer) 
            persona_display="TW"
            persona_full_name="Technical Writer"
            ;;
        researcher) 
            persona_display="Researcher"
            persona_full_name="Researcher"
            ;;
        director)
            persona_display="Director"
            persona_full_name="Director"
            ;;
        *) 
            persona_display="$persona_name"
            persona_full_name="$persona_name"
            ;;
    esac
    
    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))
        
        log "REVIEW" "${persona_display} review (cycle $cycle_number, attempt $attempt/$max_attempts)..."
        
        local pr_diff
        pr_diff=$("${ADAPTERS_DIR}/github-get-pr-diff.sh" "$pr_number" 2>/dev/null) || {
            log_warning "DIFF" "Failed to fetch PR diff, using empty"
            pr_diff=""
        }
        
        request_spacing_with_progress 2000 "${persona_display} reviewing code..."
        local review_response
        review_response=$(get_persona_review "$persona_name" "$pr_number" "$pr_diff" "$acceptance_criteria" "$cycle_number") || {
            log_warning "REVIEW" "Failed to get ${persona_display} review"
            echo "NEEDS_WORK"
            return 1
        }
        
        local review_json
        review_json=$(extract_json "$review_response")
        decision=$(echo "$review_json" | jq -r '.decision // "COMMENT"' 2>/dev/null)
        
        local review_summary
        review_summary=$(echo "$review_json" | jq -r '.summary // "Review complete"' 2>/dev/null)
        
        local review_comment
        review_comment=$(echo "$review_json" | jq -r '.comment // .review // .summary // "Review complete"' 2>/dev/null)
        
        if [[ "$decision" == "NEEDS_WORK" ]]; then
            log_warning "REVIEW" "${persona_display}: NEEDS_WORK - $review_summary"
        else
            log_success "REVIEW" "${persona_display}: $decision - $review_summary"
        fi
        
        log "GITHUB" "Posting ${persona_display} review comment..."
        local comment_output
        comment_output=$("${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$review_comment" --previous-comments "$previous_comments" 2>&1) || true
        
        local humanized_comment
        humanized_comment=$(echo "$comment_output" | sed -n '/HUMANIZED_COMMENT:/,/^---$/p' | sed '1d;$d')
        if [[ -n "$humanized_comment" ]]; then
            append_humanized_comment "$humanized_comment"
        fi
        
        if [[ "$decision" == "APPROVE" ]]; then
            log_success "REVIEW" "${persona_display} APPROVED"
            echo "APPROVE"
            return 0
        fi
        
        log "REVIEW" "${persona_display} requested changes (${decision})"
        
        if [[ $attempt -ge $max_attempts ]]; then
            log_warning "REVIEW" "Max attempts ($max_attempts) reached for ${persona_display}, moving on"
            break
        fi
        
        log "SYNTHESIS" "Director synthesizing ${persona_display} feedback..."
        request_spacing_with_progress 1500 "Director analyzing feedback..."
        
        local synthesized_response
        synthesized_response=$(synthesize_single_persona_feedback "$persona_name" "$review_response" "$cycle_number" "$attempt") || {
            log_warning "SYNTHESIS" "Failed to synthesize ${persona_display} feedback"
            continue
        }
        
        local synthesized_json
        synthesized_json=$(extract_json "$synthesized_response")
        
        local synthesized_prompt
        synthesized_prompt=$(echo "$synthesized_json" | jq -r '.prioritized_next_cycle_prompt // ""' 2>/dev/null)
        
        if [[ -z "$synthesized_prompt" || "$synthesized_prompt" == "null" ]]; then
            log_warning "SYNTHESIS" "No synthesized prompt from Director"
            continue
        fi
        
        local synthesis_comment="Looking at this more carefully, here's what I need to address: ${synthesized_prompt}"
        "${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$synthesis_comment" --previous-comments "$PREVIOUS_HUMANIZED_COMMENTS" 2>&1 || true
        
        log "ENGINEER" "Addressing ${persona_display} feedback..."

        # NOTE(angeldev): Add validation and retry loop for engineer fixes (mirrors initial implementation)
        local fix_response=""
        local fix_json=""
        local fix_attempts=0
        local max_fix_attempts="${MAX_ENGINEER_FIX_ATTEMPTS:-3}"
        local fix_valid=false

        while [[ $fix_attempts -lt $max_fix_attempts && "$fix_valid" != "true" ]]; do
            ((fix_attempts++))

            if [[ $fix_attempts -gt 1 ]]; then
                log_warning "ENGINEER" "Fix attempt $fix_attempts/$max_fix_attempts..."
                request_spacing_with_progress 2000 "Engineer retrying fix..."
            else
                request_spacing_with_progress 3000 "Engineer fixing issues..."
            fi

            local fix_status=0
            fix_response=$(fix_review_issues "$synthesized_prompt" "$full_context" "$cycle_number") || fix_status=$?

            if [[ $fix_status -ne 0 ]]; then
                log_warning "FIX" "API call failed on fix attempt $fix_attempts"
                if [[ $fix_attempts -lt $max_fix_attempts ]]; then
                    sleep 2
                    continue
                fi
                log_warning "FIX" "Failed to generate fixes after $max_fix_attempts attempts"
                continue 2
            fi

            fix_json=$(extract_json "$fix_response")

            if validate_engineer_output "$fix_json" 2>/dev/null; then
                fix_valid=true
            else
                log_warning "ENGINEER" "Invalid fix output on attempt $fix_attempts"

                if [[ $fix_attempts -lt $max_fix_attempts ]]; then
                    log "ENGINEER" "Asking Engineer to fix malformed output..."
                    fix_response=$(fix_malformed_output "$fix_response" "JSON validation failed - missing edits array or invalid structure") || continue
                    fix_json=$(extract_json "$fix_response")

                    if validate_engineer_output "$fix_json" 2>/dev/null; then
                        fix_valid=true
                    fi
                fi
            fi
        done

        if [[ "$fix_valid" != "true" ]]; then
            log_warning "FIX" "Could not get valid fix output after $max_fix_attempts attempts"
            continue
        fi

        log_success "ENGINEER" "Valid fixes generated"

        log "APPLY" "Applying ${persona_display} fixes..."
        local apply_output
        if ! apply_output=$(apply_code_changes_with_retry "$fix_response" 2); then
            log_warning "APPLY" "Failed to apply some ${persona_display} fixes"
        fi
        
        local git_status
        git_status=$(cd "$TARGET_REPO_PATH" && git status --porcelain)
        
        if [[ -z "$git_status" ]]; then
            log_warning "APPLY" "No file changes from ${persona_display} fixes"
            continue
        fi
        
        local fix_json
        fix_json=$(extract_json "$fix_response")
        local fix_commit_message
        local fix_commit_body
        fix_commit_message=$(echo "$fix_json" | jq -r '.commit_message // ""' 2>/dev/null)
        fix_commit_body=$(echo "$fix_json" | jq -r '.commit_body // ""' 2>/dev/null)

        if [[ -z "$fix_commit_message" || "$fix_commit_message" == "null" ]]; then
            local fix_summary
            fix_summary=$(echo "$fix_json" | jq -r '.summary // ""' 2>/dev/null | head -c 100)

            case "$persona_name" in
                project-manager)
                    fix_commit_message="fix(review): address scope and requirements feedback"
                    ;;
                technical-writer)
                    fix_commit_message="fix(review): improve naming and code clarity"
                    ;;
                researcher)
                    fix_commit_message="fix(review): apply best practice recommendations"
                    ;;
                *)
                    fix_commit_message="fix(review): address ${persona_display} feedback"
                    ;;
            esac

            if [[ -z "$fix_commit_body" || "$fix_commit_body" == "null" ]]; then
                local context_lines
                context_lines=$(echo "$synthesized_prompt" | head -2 | tr '\n' ' ' | head -c 200)
                if [[ -n "$context_lines" ]]; then
                    fix_commit_body="Addressing ${persona_full_name} review:
${context_lines}"
                fi
            fi
        fi

        if [[ -n "$fix_commit_body" && "$fix_commit_body" != "null" ]]; then
            fix_commit_message="${fix_commit_message}

${fix_commit_body}"
        fi
        
        log "COMMIT" "Committing ${persona_display} fixes: $fix_commit_message"
        local commit_output
        commit_output=$("${ADAPTERS_DIR}/github-commit-changes.sh" "$fix_commit_message" --all --workdir "$TARGET_REPO_PATH" 2>&1)
        
        if echo "$commit_output" | grep -q "SUCCESS"; then
            log_success "COMMIT" "Committed and pushed ${persona_display} fixes"
        else
            log_warning "COMMIT" "Commit may have failed: $commit_output"
        fi
    done
    
    echo "$decision"
    if [[ "$decision" == "APPROVE" ]]; then
        return 0
    else
        return 1
    fi
}
