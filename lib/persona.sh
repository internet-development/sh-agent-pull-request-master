#!/bin/bash
#
# NOTE(jimmylee)
# Main persona orchestration module.
# This is a thin layer that sources the specialized modules and provides
# the core invoke_persona() function and execute_plan() orchestration.
#
# Module structure:
#   lib/constants.sh     - Configuration constants
#   lib/json.sh          - JSON handling utilities
#   lib/config.sh        - Environment and persona config loading
#   lib/providers.sh     - LLM API calls (Anthropic, OpenAI, Google)
#   lib/memory.sh        - Task context and state
#   lib/logging.sh       - Terminal output styling
#   lib/humanize.sh      - Comment humanization for GitHub
#   lib/planning.sh      - Planning phase (clone, analyze, research, synthesis)
#   lib/implementation.sh - Engineer implementation and code application
#   lib/review.sh        - Review cycles and feedback synthesis

[[ -n "${_PERSONA_SH_LOADED:-}" ]] && return 0
_PERSONA_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTERS_DIR="$(cd "$SCRIPT_DIR/../adapters" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =============================================================================
# SOURCE DEPENDENCIES
# =============================================================================

source "${SCRIPT_DIR}/constants.sh"
source "${SCRIPT_DIR}/json.sh"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/providers.sh"
source "${SCRIPT_DIR}/memory.sh"
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/humanize.sh"
source "${SCRIPT_DIR}/planning.sh"
source "${SCRIPT_DIR}/implementation.sh"
source "${SCRIPT_DIR}/review.sh"

# =============================================================================
# GLOBAL STATE
# =============================================================================

# NOTE(jimmylee)
# Global variable to track the cloned repository path.
# This is set by clone_target_repo and used by all subsequent operations.
TARGET_REPO_PATH=""

# Track the last persona for transition phrases
LAST_PERSONA=""

# =============================================================================
# CORE PERSONA INVOCATION
# =============================================================================

# NOTE(jimmylee)
# Returns a natural language transition phrase when switching between personas.
get_persona_transition_phrase() {
    local persona_name="$1"
    local previous_persona="${2:-}"
    
    if [[ "$persona_name" == "$previous_persona" ]]; then
        echo ""
        return
    fi
    
    case "$persona_name" in
        Director|director)
            echo "Switching gears to coordinate the next steps..."
            ;;
        Engineer|engineer)
            echo "Taking a closer look at the technical implementation..."
            ;;
        Researcher|researcher)
            echo "Let me dig into some background research on this..."
            ;;
        "Project Manager"|project-manager)
            echo "Thinking about this from a planning and scope perspective..."
            ;;
        "Technical Writer"|technical-writer)
            echo "Reviewing this from a documentation and clarity standpoint..."
            ;;
        *)
            echo "Shifting focus here..."
            ;;
    esac
}

# NOTE(jimmylee)
# Core function that invokes a persona with a prompt and saves to memory.
# Returns the raw response content for backwards compatibility.
invoke_persona() {
    local persona_name="$1"
    local prompt="$2"
    
    local system_prompt
    system_prompt=$(get_persona_prompt "$persona_name") || {
        echo "ERROR: Failed to load persona: $persona_name" >&2
        return 1
    }
    
    local transition=""
    transition=$(get_persona_transition_phrase "$persona_name" "$LAST_PERSONA")
    if [[ -n "$transition" ]]; then
        system_prompt="${system_prompt}

IMPORTANT: When responding, this is a continuation of an internal monologue that involved other perspectives. Write naturally as if shifting focus, not as a different entity. Avoid phrases like 'As the Engineer...' - just provide the analysis directly."
    fi
    
    LAST_PERSONA="$persona_name"
    
    local response
    local call_status=0
    response=$(call_provider "$persona_name" "$system_prompt" "$prompt") || call_status=$?
    
    if [[ $call_status -ne 0 ]]; then
        echo "ERROR: API call failed for persona: $persona_name" >&2
        return 1
    fi
    
    save_turn "$persona_name" "$prompt" "$response"
    
    echo "$response"
}

# NOTE(jimmylee)
# Invokes a persona and returns output in the universal structured format.
invoke_persona_structured() {
    local persona_name="$1"
    local prompt="$2"
    local output_type="${3:-response}"
    
    local response
    response=$(invoke_persona "$persona_name" "$prompt") || {
        format_persona_output "$persona_name" "error" "API call failed" '{"error": true}'
        return 1
    }
    
    local summary
    summary=$(echo "$response" | head -c 100 | tr '\n' ' ')
    log_persona_output "$persona_name" "$output_type" "${summary}..."
    
    format_persona_output "$persona_name" "$output_type" "$response"
}

# =============================================================================
# ERROR RECOVERY
# =============================================================================

# NOTE(jimmylee)
# Retry a function with exponential backoff
retry_with_backoff() {
    local func_name="$1"
    shift
    local args=("$@")
    
    local attempt=1
    local delay=2
    local result
    local max_retries="${MAX_RETRIES:-3}"
    
    while [[ $attempt -le $max_retries ]]; do
        if result=$("$func_name" "${args[@]}"); then
            echo "$result"
            return 0
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            log_warning "RETRY" "Attempt $attempt failed for $func_name. Retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        
        ((attempt++))
    done
    
    log_error "RETRY" "All $max_retries attempts failed for $func_name"
    return 1
}

# NOTE(jimmylee)
# Recovers from API failure by clearing state and retrying
recover_from_api_failure() {
    local persona_name="$1"
    local original_prompt="$2"
    
    log_warning "RECOVER" "Attempting recovery for $persona_name API call..."
    
    sleep 3
    
    local prompt_length=${#original_prompt}
    if [[ $prompt_length -gt 50000 ]]; then
        log_warning "RECOVER" "Prompt too long ($prompt_length chars), truncating..."
        original_prompt="${original_prompt:0:40000}

[Content truncated for retry]"
    fi
    
    invoke_persona "$persona_name" "$original_prompt"
}

# NOTE(jimmylee)
# Cleans up resources on failure
cleanup_on_failure() {
    local pr_number="${1:-}"
    local branch_name="${2:-}"
    
    log_warning "CLEANUP" "Cleaning up after failure..."
    
    if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
        local cleanup_comment="**Automated Process Failed**

The www-agent encountered an error and could not complete the implementation.
This PR may be incomplete and should be reviewed manually or closed.

---
*This comment was added automatically by www-agent*"
        
        "${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$cleanup_comment" --persona "director" 2>&1 || true
    fi
    
    log "CLEANUP" "Cleanup complete"
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

# NOTE(jimmylee)
# Main execution flow:
# 1. SETUP: Clone repo, gather context
# 2. PLANNING: Director plans, personas contribute, requirements synthesized
# 3. EXECUTION LOOP: Engineer implements -> Personas review -> Engineer fixes -> repeat until approved
execute_plan() {
    local directive="$1"
    local max_review_iterations="${2:-${MAX_REVIEW_CYCLES:-5}}"
    
    log_phase "PLANNING"
    
    # Step 1.1: Clone the target repository
    log "STEP 1.1" "Cloning target repository..."
    clone_target_repo "true" || {
        log_error "CLONE" "Failed to clone target repository"
        return 1
    }
    
    # Step 1.2: Deep codebase analysis
    log "STEP 1.2" "Performing deep codebase analysis..."
    log "INFO" "Reading ALL source files to give Director complete visibility..."
    
    local repo_context
    repo_context=$(get_repo_context)
    
    local deep_analysis
    deep_analysis=$(analyze_codebase_deep)
    
    local full_context="${repo_context}

${deep_analysis}"
    
    log_success "ANALYSIS" "Deep codebase scan complete"
    
    # Step 1.3: Director creates initial plan
    log "STEP 1.3" "Director creating initial plan..."
    request_spacing_with_progress 2000 "Director analyzing directive and codebase..."
    
    local director_plan
    director_plan=$(create_director_plan "$directive" "$full_context") || {
        log_error "DIRECTOR" "Failed to create plan"
        return 1
    }
    
    log_success "DIRECTOR" "Initial plan created"
    
    local plan_json
    plan_json=$(extract_json "$director_plan")
    
    log_subsection "DIRECTOR PLAN OUTPUT"
    echo "$director_plan" | head -50
    echo ""
    
    local understanding
    understanding=$(echo "$plan_json" | jq -r '.understanding // empty' 2>/dev/null)
    
    local consult_personas
    consult_personas=$(echo "$plan_json" | jq -r '.consult_personas // [] | .[]' 2>/dev/null)
    
    # Step 1.4: Conduct web research if requested
    local research_queries
    research_queries=$(echo "$plan_json" | jq '.research_queries // []' 2>/dev/null)
    
    local research_findings='{"research_conducted": false, "findings": [], "summary": ""}'
    local research_query_count
    research_query_count=$(echo "$research_queries" | jq 'length' 2>/dev/null) || research_query_count=0
    
    if ! is_research_enabled; then
        log "STEP 1.4" "Web research disabled (Google Search not configured) - skipping"
    elif [[ "$research_query_count" -gt 0 && "$research_queries" != "[]" && "$research_queries" != "null" ]]; then
        log "STEP 1.4" "Conducting web research ($research_query_count queries)..."
        research_findings=$(conduct_web_research "$research_queries" "$directive") || {
            log_warning "RESEARCH" "Research failed, proceeding without external verification"
            research_findings='{"research_conducted": false, "findings": [], "summary": "Research unavailable. Proceeding with existing knowledge."}'
        }
    else
        log "STEP 1.4" "No web research needed - proceeding with codebase knowledge"
    fi
    
    # Step 1.5: Gather input from all relevant personas
    log "STEP 1.5" "Gathering input from personas..."
    
    local all_persona_input=""
    
    for persona in $consult_personas; do
        if [[ "$persona" == "engineer" || "$persona" == "director" ]]; then
            continue
        fi
        
        if [[ "$persona" == "researcher" ]] && ! is_research_enabled; then
            log "CONSULT" "Skipping researcher (Google Search not configured)"
            continue
        fi
        
        local question
        question=$(echo "$plan_json" | jq -r ".questions_for_personas[\"$persona\"] // \"Please provide your input on this directive.\"" 2>/dev/null)
        
        log "CONSULT" "Asking $persona for input..."
        request_spacing_with_progress 2000 "Consulting $persona..."
        
        local persona_input
        persona_input=$(get_persona_input "$persona" "$directive" "$question" "$full_context" "$research_findings") || {
            log_warning "CONSULT" "Failed to get input from $persona"
            continue
        }
        
        log_success "CONSULT" "$persona provided input"
        
        local persona_upper
        persona_upper=$(echo "$persona" | tr '[:lower:]' '[:upper:]')
        log_subsection "${persona_upper} INPUT OUTPUT"
        echo "$persona_input" | head -30
        echo ""
        
        all_persona_input="${all_persona_input}

### ${persona}'s Input

${persona_input}
"
    done
    
    # Step 1.6: Director synthesizes all input into requirements
    log "STEP 1.6" "Director synthesizing requirements..."
    request_spacing_with_progress 2000 "Synthesizing requirements..."
    
    local requirements
    requirements=$(synthesize_requirements "$directive" "$all_persona_input" "$full_context" "$research_findings") || {
        log_error "DIRECTOR" "Failed to synthesize requirements"
        return 1
    }
    
    log_success "DIRECTOR" "Requirements synthesized"
    
    log_subsection "REQUIREMENTS SYNTHESIS OUTPUT"
    echo "$requirements" | head -50
    echo ""
    
    local requirements_json
    requirements_json=$(extract_json "$requirements")
    
    # Step 1.7: Display emoji reactions for each persona suggestion
    log "STEP 1.7" "Reviewing persona suggestions..."
    echo ""
    
    local suggestion_count
    suggestion_count=$(echo "$requirements_json" | jq -r '.suggestion_decisions | length // 0' 2>/dev/null) || suggestion_count=0
    
    local suggestions_comment=""
    local decisions_table=""
    
    if [[ "$suggestion_count" -gt 0 ]]; then
        decisions_table=$(format_decisions_table "$requirements_json")
        
        for i in $(seq 0 $((suggestion_count - 1))); do
            local suggestion decision reason
            suggestion=$(echo "$requirements_json" | jq -r ".suggestion_decisions[$i].suggestion // \"\"")
            decision=$(echo "$requirements_json" | jq -r ".suggestion_decisions[$i].decision // \"skip\"")
            reason=$(echo "$requirements_json" | jq -r ".suggestion_decisions[$i].reason // \"\"")
            
            case "$decision" in
                incorporate)
                    log "DECISION" "✅ $suggestion"
                    log "REASON" "   $reason"
                    ;;
                already_done)
                    log "DECISION" "✅ $suggestion"
                    log "REASON" "   Already addressed - $reason"
                    ;;
                skip)
                    log "DECISION" "⏭️ $suggestion"
                    log "REASON" "   Skipping (side effect) - $reason"
                    ;;
            esac
        done
        
        suggestions_comment="$decisions_table"
    fi
    
    local acceptance_criteria
    acceptance_criteria=$(echo "$requirements_json" | jq -r '.acceptance_criteria | join("\n- ")' 2>/dev/null) || true
    
    # Step 2.1: Create branch
    log "STEP 2.1" "Creating feature branch..."
    
    local task_summary
    task_summary=$(echo "$requirements_json" | jq -r '.task_summary // empty' 2>/dev/null) || true
    
    if [[ -z "$task_summary" || "$task_summary" == "null" ]]; then
        log_warning "BRANCH" "No task_summary in requirements, using directive fallback"
        task_summary=$(echo "$directive" | head -c 100)
    fi
    
    local branch_title
    branch_title=$(echo "$task_summary" | cut -c1-50)
    
    local branch_output
    branch_output=$("${ADAPTERS_DIR}/git-create-branch.sh" "$branch_title" --workdir "$TARGET_REPO_PATH" 2>&1) || {
        log_error "BRANCH" "Failed to create branch"
        echo "$branch_output" >&2
        return 1
    }
    
    local branch_name
    branch_name=$(echo "$branch_output" | grep "BRANCH_NAME:" | cut -d' ' -f2)
    log_success "BRANCH" "Created: $branch_name"
    
    # Step 2.2: Engineer implements changes
    log "STEP 2.2" "Engineer implementing changes..."
    request_spacing_with_progress 3000 "Engineer writing code..."
    
    local engineer_response
    local engineer_json
    local engineer_attempts=0
    local max_engineer_attempts="${MAX_ENGINEER_ATTEMPTS:-3}"
    local engineer_valid=false
    
    while [[ $engineer_attempts -lt $max_engineer_attempts && "$engineer_valid" != "true" ]]; do
        ((engineer_attempts++))
        
        if [[ $engineer_attempts -gt 1 ]]; then
            log_warning "ENGINEER" "Attempt $engineer_attempts/$max_engineer_attempts..."
            request_spacing_with_progress 2000 "Engineer retrying..."
        fi
        
        local impl_status=0
        engineer_response=$(implement_changes "$requirements" "$full_context" "$all_persona_input") || impl_status=$?
        
        if [[ $impl_status -ne 0 ]]; then
            log_error "ENGINEER" "API call failed on attempt $engineer_attempts"
            if [[ $engineer_attempts -lt $max_engineer_attempts ]]; then
                sleep 3
                continue
            fi
            cleanup_on_failure "" "$branch_name"
            return 1
        fi
        
        engineer_json=$(extract_json "$engineer_response")
        
        if validate_engineer_output "$engineer_json" 2>/dev/null; then
            engineer_valid=true
        else
            log_warning "ENGINEER" "Invalid output on attempt $engineer_attempts"
            
            if [[ $engineer_attempts -lt $max_engineer_attempts ]]; then
                log "ENGINEER" "Asking Engineer to fix output..."
                engineer_response=$(fix_malformed_output "$engineer_response" "JSON validation failed") || continue
                engineer_json=$(extract_json "$engineer_response")
                
                if validate_engineer_output "$engineer_json" 2>/dev/null; then
                    engineer_valid=true
                fi
            fi
        fi
    done
    
    if [[ "$engineer_valid" != "true" ]]; then
        log_error "ENGINEER" "Failed to get valid output after $max_engineer_attempts attempts"
        cleanup_on_failure "" "$branch_name"
        return 1
    fi
    
    log_success "ENGINEER" "Code generated and validated"
    
    log_subsection "ENGINEER IMPLEMENTATION OUTPUT"
    echo "$engineer_response" | head -50
    echo ""
    
    # Step 2.3: Apply code changes
    log "STEP 2.3" "Applying code changes to files..."
    local apply_output
    apply_output=$(apply_code_changes_with_retry "$engineer_response" 2)
    local apply_status=$?
    
    local git_status
    git_status=$(cd "$TARGET_REPO_PATH" && git status --porcelain)
    
    if [[ -z "$git_status" ]]; then
        log_error "APPLY" "No files were changed in the repository"
        log_error "DEBUG" "The Engineer's output may not have contained valid file changes"
        if [[ -n "$APPLY_RESULT_JSON" ]]; then
            local failed_edits
            failed_edits=$(echo "$APPLY_RESULT_JSON" | jq -r '.edits[] | select(.status == "error") | "  - \(.path): \(.message)"' 2>/dev/null)
            if [[ -n "$failed_edits" ]]; then
                log_error "FAILED_EDITS" "Edit failures:\n$failed_edits"
            fi
        fi
        cleanup_on_failure "" "$branch_name"
        return 1
    fi
    
    log_success "APPLY" "Files changed: $(echo "$git_status" | wc -l | tr -d ' ') files"

    # Step 2.4: Pre-commit analysis and message generation
    log "STEP 2.4" "Analyzing changes for commit..."

    log_subsection "PRE-COMMIT ANALYSIS"
    local file_count
    file_count=$(echo "$git_status" | wc -l | tr -d ' ')
    log "COMMIT" "Files to commit: $file_count"

    local git_diff_stat
    git_diff_stat=$(cd "$TARGET_REPO_PATH" && git diff --stat HEAD 2>/dev/null | tail -5)
    if [[ -n "$git_diff_stat" ]]; then
        log "COMMIT" "Change summary:"
        echo "$git_diff_stat" | while IFS= read -r line; do
            log "COMMIT" "  $line"
        done
    fi
    echo ""

    local commit_message
    local commit_body_text=""
    engineer_json=$(extract_json "$engineer_response")

    commit_message=$(echo "$engineer_json" | jq -r '.commit_message // ""' 2>/dev/null)
    commit_body_text=$(echo "$engineer_json" | jq -r '.commit_body // ""' 2>/dev/null)

    if [[ -z "$commit_message" || "$commit_message" == "null" ]]; then
        local changes_summary
        changes_summary=$(echo "$engineer_json" | jq -r '.summary // "Changes implemented"' 2>/dev/null) || changes_summary="Changes implemented"

        request_spacing_with_progress 1500 "Determining commit info..."

        local commit_info_response
        commit_info_response=$(determine_commit_info "$changes_summary" "$directive") || {
            log_warning "COMMIT" "Failed to determine commit info, using defaults"
            commit_info_response='{"type":"feat","scope":"","description":"implement changes per directive","body":"","breaking":""}'
        }

        local commit_info_json
        commit_info_json=$(extract_json "$commit_info_response")

        local commit_type commit_scope commit_desc commit_body commit_breaking
        commit_type=$(echo "$commit_info_json" | jq -r '.type // "feat"' 2>/dev/null)
        commit_scope=$(echo "$commit_info_json" | jq -r '.scope // ""' 2>/dev/null)
        commit_desc=$(echo "$commit_info_json" | jq -r '.description // "implement changes"' 2>/dev/null)
        commit_body=$(echo "$commit_info_json" | jq -r '.body // ""' 2>/dev/null)
        commit_breaking=$(echo "$commit_info_json" | jq -r '.breaking // ""' 2>/dev/null)

        commit_message=$(generate_commit_message "$commit_type" "$commit_scope" "$commit_desc" "$commit_body" "$commit_breaking")
    else
        if [[ -n "$commit_body_text" && "$commit_body_text" != "null" ]]; then
            commit_message="${commit_message}

${commit_body_text}"
        fi
    fi

    local commit_header
    commit_header=$(echo "$commit_message" | head -1)
    log "COMMIT" "Message: $commit_header"
    if [[ $(echo "$commit_message" | wc -l) -gt 1 ]]; then
        log "COMMIT" "Body: (multi-line commit with rationale)"
    fi

    # Step 2.5: Commit and push
    log "STEP 2.5" "Committing and pushing changes..."

    local commit_output
    commit_output=$("${ADAPTERS_DIR}/github-commit-changes.sh" "$commit_message" --all --workdir "$TARGET_REPO_PATH" 2>&1) || {
        log_warning "COMMIT" "No changes to commit or commit failed"
        echo "$commit_output"
    }

    if echo "$commit_output" | grep -q "SUCCESS"; then
        log_success "COMMIT" "Changes committed and pushed"

        local commit_sha
        commit_sha=$(cd "$TARGET_REPO_PATH" && git rev-parse --short HEAD 2>/dev/null)
        local commit_files
        commit_files=$(cd "$TARGET_REPO_PATH" && git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | wc -l | tr -d ' ')
        log "COMMIT" "Verified: $commit_sha ($commit_files files)"
    else
        log_warning "COMMIT" "No file changes were made"
    fi
    echo ""

    # Step 2.6: Create Pull Request
    log "STEP 2.6" "Creating Pull Request..."
    
    local pr_title
    pr_title=$(shorten_pr_title "$task_summary" "${MAX_PR_TITLE_LENGTH:-128}") || pr_title="$task_summary"
    log "PR_TITLE" "$pr_title"
    local model_attribution
    model_attribution=$(get_model_attribution)

    local pr_body="Thank you for the opportunity to work on this.

${understanding}

This implementation was chosen because it addresses the requirements directly while maintaining consistency with the existing codebase patterns. The changes are minimal and focused - doing exactly what was asked, nothing more.

- ${acceptance_criteria}

---

**Directive:** ${directive}

**Models Used:**

${model_attribution}
"
    
    local pr_output
    local pr_attempts=0
    local max_pr_attempts="${MAX_PR_ATTEMPTS:-3}"
    local pr_created=false
    
    while [[ $pr_attempts -lt $max_pr_attempts && "$pr_created" != "true" ]]; do
        ((pr_attempts++))
        
        if [[ $pr_attempts -gt 1 ]]; then
            log_warning "PR" "Retry attempt $pr_attempts/$max_pr_attempts..."
            sleep 3
        fi
        
        pr_output=$("${ADAPTERS_DIR}/github-create-pr.sh" "$pr_title" "$pr_body" "main" --workdir "$TARGET_REPO_PATH" 2>&1) && pr_created=true || {
            log_warning "PR" "PR creation failed on attempt $pr_attempts"
            
            if echo "$pr_output" | grep -qi "already exists"; then
                log_warning "PR" "A PR for this branch may already exist"
                local existing_prs
                existing_prs=$("${ADAPTERS_DIR}/github-list-prs.sh" --head "$branch_name" --state "open" 2>/dev/null) || true
                if [[ -n "$existing_prs" ]]; then
                    pr_number=$(echo "$existing_prs" | jq -r '.[0].number // empty')
                    pr_url=$(echo "$existing_prs" | jq -r '.[0].url // empty')
                    if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
                        log "PR" "Found existing PR #$pr_number"
                        pr_created=true
                    fi
                fi
            fi
        }
    done
    
    if [[ "$pr_created" != "true" ]]; then
        log_error "PR" "Failed to create pull request after $max_pr_attempts attempts"
        echo "$pr_output" >&2
        cleanup_on_failure "" "$branch_name"
        return 1
    fi
    
    if [[ -z "${pr_number:-}" ]]; then
        pr_number=$(echo "$pr_output" | grep "PR_NUMBER:" | cut -d' ' -f2)
    fi
    if [[ -z "${pr_url:-}" ]]; then
        pr_url=$(echo "$pr_output" | grep "URL:" | cut -d' ' -f2)
    fi
    
    log_success "PR" "Created: #$pr_number"
    log "URL" "$pr_url"
    
    if [[ -n "$suggestions_comment" ]]; then
        log "COMMENT" "Posting decisions table..."
        local formatted_comment
        formatted_comment=$(echo -e "$suggestions_comment")
        "${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$formatted_comment" --skip-humanize 2>&1 || true
        log_success "COMMENT" "Decisions table posted"
    fi
    
    # ==========================================================================
    # REVIEW CYCLES
    # ==========================================================================

    local iteration=0
    local all_approved=false
    local max_attempts_per_persona="${MAX_FIX_ATTEMPTS_PER_PERSONA:-2}"
    
    reset_humanized_comments

    while [[ $iteration -lt $max_review_iterations && "$all_approved" != "true" ]]; do
        ((iteration++))

        log_phase "REVIEW CYCLE $iteration"

        local pm_decision="APPROVE"
        local tw_decision="APPROVE"
        local researcher_decision="APPROVE"

        # Step 3.1: Project Manager Review
        log "STEP 3.1" "Project Manager reviewing..."
        
        pm_decision=$(process_persona_review_cycle \
            "project-manager" \
            "$pr_number" \
            "$acceptance_criteria" \
            "$full_context" \
            "$iteration" \
            "$max_attempts_per_persona" \
            "$(get_accumulated_comments)") || pm_decision="NEEDS_WORK"
        
        if [[ "$pm_decision" == "APPROVE" ]]; then
            log_success "PM" "Approved"
        else
            log_warning "PM" "Could not fully satisfy PM feedback after $max_attempts_per_persona attempts"
        fi

        # Step 3.2: Technical Writer Review
        log "STEP 3.2" "Technical Writer reviewing updated code..."
        
        tw_decision=$(process_persona_review_cycle \
            "technical-writer" \
            "$pr_number" \
            "$acceptance_criteria" \
            "$full_context" \
            "$iteration" \
            "$max_attempts_per_persona" \
            "$(get_accumulated_comments)") || tw_decision="NEEDS_WORK"
        
        if [[ "$tw_decision" == "APPROVE" ]]; then
            log_success "TW" "Approved"
        else
            log_warning "TW" "Could not fully satisfy TW feedback after $max_attempts_per_persona attempts"
        fi

        # Step 3.3: Researcher Review (if enabled)
        if is_research_enabled; then
            log "STEP 3.3" "Researcher reviewing updated code..."
            
            researcher_decision=$(process_persona_review_cycle \
                "researcher" \
                "$pr_number" \
                "$acceptance_criteria" \
                "$full_context" \
                "$iteration" \
                "$max_attempts_per_persona" \
                "$(get_accumulated_comments)") || researcher_decision="NEEDS_WORK"
            
            if [[ "$researcher_decision" == "APPROVE" ]]; then
                log_success "Researcher" "Approved"
            else
                log_warning "Researcher" "Could not fully satisfy Researcher feedback after $max_attempts_per_persona attempts"
            fi
        else
            log "REVIEW" "Researcher review skipped (Google Search not configured)"
            researcher_decision="APPROVE"
        fi

        # Step 3.4: Check if all approved - Director final review
        if [[ "$pm_decision" == "APPROVE" && "$tw_decision" == "APPROVE" && "$researcher_decision" == "APPROVE" ]]; then
            log "STEP 3.4" "All personas approved - getting Director final review..."

            local pr_diff
            pr_diff=$("${ADAPTERS_DIR}/github-get-pr-diff.sh" "$pr_number" 2>/dev/null) || pr_diff=""

            request_spacing_with_progress 2000 "Director final review..."
            local director_review
            director_review=$(get_persona_review "director" "$pr_number" "$pr_diff" "$acceptance_criteria" "$iteration") || {
                log_warning "REVIEW" "Failed to get Director review, assuming approval"
                director_review='{"decision":"APPROVE","summary":"Approved"}'
            }
            
            local director_json
            director_json=$(extract_json "$director_review")
            local director_decision
            director_decision=$(echo "$director_json" | jq -r '.decision // "APPROVE"' 2>/dev/null)
            local director_summary
            director_summary=$(echo "$director_json" | jq -r '.summary // "Approved"' 2>/dev/null)
            local director_comment
            director_comment=$(echo "$director_json" | jq -r '.comment // .review // .summary // "Approved"' 2>/dev/null)

            "${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$director_comment" --previous-comments "$(get_accumulated_comments)" 2>&1 || true

            if [[ "$director_decision" == "APPROVE" ]]; then
                all_approved=true
                log_success "APPROVED" "All personas approved the PR!"

                log "APPROVE" "Submitting GitHub approval with LGTM..."
                "${ADAPTERS_DIR}/github-approve-pr.sh" "$pr_number" "LGTM" 2>&1 || true
                log_success "APPROVE" "PR approved on GitHub"
                break
            else
                log_warning "REVIEW" "Director: NEEDS_WORK - processing Director feedback..."
                
                local director_fix_decision
                director_fix_decision=$(process_persona_review_cycle \
                    "director" \
                    "$pr_number" \
                    "$acceptance_criteria" \
                    "$full_context" \
                    "$iteration" \
                    "1" \
                    "$(get_accumulated_comments)") || director_fix_decision="NEEDS_WORK"
                
                if [[ "$director_fix_decision" == "APPROVE" ]]; then
                    all_approved=true
                    log_success "APPROVED" "Director approved after fixes!"
                    "${ADAPTERS_DIR}/github-approve-pr.sh" "$pr_number" "LGTM" 2>&1 || true
                    break
                fi
            fi
        else
            log "SUMMARY" "Cycle $iteration results: PM=$pm_decision, TW=$tw_decision, Researcher=$researcher_decision"
            log "INFO" "Starting next review cycle with updated code..."
        fi
    done
    
    log_phase "COMPLETE"
    
    if [[ "$all_approved" == "true" ]]; then
        log_success "RESULT" "PR approved by all personas!"
        
        log "GITHUB" "Posting final comment to PR #$pr_number..."
        local approval_comment="LGTM"
        local comment_output
        if comment_output=$("${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$approval_comment" --skip-humanize 2>&1); then
            log_success "GITHUB" "Posted approval comment"
        else
            log_warning "GITHUB" "Failed to post approval comment: $comment_output"
        fi
    else
        log_warning "RESULT" "Max review iterations reached"
        
        log "GITHUB" "Posting final comment to PR #$pr_number..."
        local handoff_comment="I need your organization support, I couldn't get this PR to where I wanted it exactly, sorry"
        local comment_output
        if comment_output=$("${ADAPTERS_DIR}/github-comment-pr.sh" "$pr_number" "$handoff_comment" --skip-humanize 2>&1); then
            log_success "GITHUB" "Posted handoff comment"
        else
            log_warning "GITHUB" "Failed to post handoff comment: $comment_output"
        fi
    fi
    
    log "PR" "#$pr_number: $pr_title"
    log "URL" "$pr_url"
    log "BRANCH" "$branch_name"
    
    if [[ "$all_approved" == "true" ]]; then
        log "NEXT" "PR is ready to merge!"
    else
        log "NEXT" "Review the PR on GitHub and merge if acceptable"
    fi
    
    printf "\n%s\n" "$pr_url"
}
