#!/bin/bash
#
# NOTE(jimmylee)
# Main entry point for www-agent. Commands:
#   ./agent.sh run                 - Run agent using .directive file
#   ./agent.sh dry-run             - Test full flow without executing
#   ./agent.sh new                 - Clear current session
#   ./agent.sh status              - Show status
#   ./agent.sh test-models         - Test API connections
#   ./agent.sh clear-context       - Clear all context

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${AGENT_DIR}/lib/config.sh"
source "${AGENT_DIR}/lib/memory.sh"
source "${AGENT_DIR}/lib/logging.sh"

load_env

# NOTE(angeldev)
# Clears the .workrepo directory to ensure a clean working state.
# Called at session start and end to prevent stale state between runs.
clear_workrepo() {
    local workrepo_dir="${AGENT_DIR}/.workrepo"
    if [[ -d "$workrepo_dir" ]]; then
        log "CLEANUP" "Clearing .workrepo directory..."
        rm -rf "$workrepo_dir"
        log_success "CLEANUP" "Work directory cleared"
    fi
}

# NOTE(angeldev)
# Session cleanup handler - clears workrepo on exit.
# This ensures no stale repos remain between sessions.
cleanup_session() {
    clear_workrepo
}

# NOTE(jimmylee)
# Ensure Rust tools are built before running the agent.
# This is idempotent - only rebuilds if source has changed.
if [[ ! -x "${AGENT_DIR}/tools/apply-edits/target/release/apply-edits" ]]; then
    echo "Building required tools..."
    "${AGENT_DIR}/scripts/ensure-tools.sh" || {
        echo "ERROR: Failed to build required tools. Is Rust installed?" >&2
        echo "Install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
        exit 1
    }
fi

# Setup graceful shutdown handler
setup_shutdown_handler

# Legacy color variables (for backward compatibility)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# NOTE(jimmylee)
# Legacy print functions - now wrap the new logging system
print_header() {
    print_section_header "$1"
}

print_success() {
    echo -e "${COLOR_GREEN}$1${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_RED}$1${COLOR_RESET}"
}

print_warning() {
    echo -e "${COLOR_YELLOW}$1${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

# NOTE(jimmylee)
# Reads the directive from .directive file in the repo root
read_directive() {
    local directive_file="${AGENT_DIR}/.directive"
    
    if [[ ! -f "$directive_file" ]]; then
        log_error "FILE" "No .directive file found in repository root."
        log "INFO" "Create a .directive file with your goal/objective."
        exit 1
    fi
    
    local directive
    directive=$(cat "$directive_file")
    
    if [[ -z "$directive" || "$directive" =~ ^[[:space:]]*$ ]]; then
        log_error "FILE" ".directive file is empty."
        exit 1
    fi
    
    echo "$directive"
}

# NOTE(jimmylee)
# Processes a directive by initializing a task and invoking the Director
cmd_run() {
    local dry_run="${1:-false}"
    
    local directive
    directive=$(read_directive)
    
    log_directive "$directive"
    
    if ! validate_env 2>/dev/null; then
        log_error "ENVIRONMENT" "Validation failed. Run '$0 status' for details."
        exit 1
    fi
    
    # Flush context, temp files, and workrepo at the start of each session
    flush_context
    clear_tmp_dir
    clear_workrepo
    log "CONTEXT" "Flushed for new session."

    # Set up cleanup on session end (exit, error, or interrupt)
    trap cleanup_session EXIT
    
    local task_id
    task_id=$(init_task)
    log_success "TASK" "Started new task: $task_id"
    
    if [[ "$dry_run" == "true" ]]; then
        log_warning "MODE" "DRY RUN - Testing full flow without executing changes"
        echo ""
        cmd_dry_run_flow "$directive"
        return
    fi
    
    log "PROCESSING" "Starting execution pipeline..."
    echo ""
    
    source "${AGENT_DIR}/lib/persona.sh"
    
    # Run execute_plan directly (not in subshell) so we can see all output
    execute_plan "$directive" || {
        log_error "FAILED" "Failed to execute plan"
        exit 1
    }
}

# NOTE(jimmylee)
# Dry run mode: tests all integrations without making real changes
cmd_dry_run_flow() {
    local directive="$1"
    
    source "${AGENT_DIR}/lib/providers.sh"
    source "${AGENT_DIR}/lib/persona.sh"
    source "${AGENT_DIR}/lib/github.sh"
    
    local all_passed=true
    local test_results=()
    
    print_section_header "Dry Run: Testing All Integrations"
    
    # Get configured models from config
    local anthropic_model openai_model
    anthropic_model=$(get_model_by_category "programming" 2>/dev/null) || anthropic_model="claude-opus-4-5"
    openai_model=$(get_model_by_category "human-simulated" 2>/dev/null) || openai_model="gpt-5.2-chat-latest"
    
    # 1. Test Anthropic (from config)
    log "ANTHROPIC" "Testing ${anthropic_model}..."
    if [[ -n "${API_KEY_ANTHROPIC:-}" ]]; then
        request_spacing 500
        local anthropic_result
        anthropic_result=$(call_anthropic "You are a test assistant." "Reply with exactly: DRY_RUN_OK" 50 "$anthropic_model" 2>&1) || true
        if echo "$anthropic_result" | grep -qi "DRY_RUN_OK\|ok\|dry"; then
            log_success "ANTHROPIC" "PASS - ${anthropic_model} responding"
            test_results+=("Anthropic (${anthropic_model}): PASS")
        else
            log_error "ANTHROPIC" "FAIL - Unexpected response: $anthropic_result"
            test_results+=("Anthropic (${anthropic_model}): FAIL")
            all_passed=false
        fi
    else
        log_error "ANTHROPIC" "SKIP - API_KEY_ANTHROPIC not set"
        test_results+=("Anthropic: SKIP")
        all_passed=false
    fi
    
    # 2. Test OpenAI (GPT-5.2 from config)
    log "OPENAI" "Testing ${openai_model}..."
    if [[ -n "${API_KEY_OPEN_AI:-}" ]]; then
        request_spacing 500
        local openai_result
        # NOTE(jimmylee): GPT-5.x models need more tokens (100+) for responses
        openai_result=$(call_openai "You are a test assistant." "Reply with exactly: DRY_RUN_OK" 100 "$openai_model" 2>&1) || true
        if echo "$openai_result" | grep -qi "DRY_RUN_OK\|ok\|dry"; then
            log_success "OPENAI" "PASS - ${openai_model} responding"
            test_results+=("OpenAI (${openai_model}): PASS")
        else
            log_error "OPENAI" "FAIL - Unexpected response: $openai_result"
            test_results+=("OpenAI (${openai_model}): FAIL")
            all_passed=false
        fi
    else
        log_warning "OPENAI" "SKIP - API_KEY_OPEN_AI not set (optional)"
        test_results+=("OpenAI: SKIP (optional)")
    fi
    
    # 3. Test Google Custom Search
    log "GOOGLE" "Testing Google Custom Search API..."
    if [[ -n "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" && -n "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        request_spacing 500
        local google_result
        google_result=$(call_google_search "test query" 1 2>&1) || true
        
        if echo "$google_result" | jq -e '.searchInformation' > /dev/null 2>&1; then
            log_success "GOOGLE" "PASS - Search API responding"
            test_results+=("Google Search: PASS")
        else
            log_error "GOOGLE" "FAIL - API error: $google_result"
            test_results+=("Google Search: FAIL")
            all_passed=false
        fi
    else
        log_warning "GOOGLE" "SKIP - Google Search not configured (optional)"
        test_results+=("Google Search: SKIP (optional)")
    fi
    
    # 4. Test GitHub API
    log "GITHUB" "Testing GitHub API..."
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        request_spacing 500
        local gh_user
        gh_user=$(github_get_user 2>&1) || true
        if [[ -n "$gh_user" && ! "$gh_user" =~ "ERROR" ]]; then
            log_success "GITHUB" "PASS - Authenticated as: $gh_user"
            test_results+=("GitHub API: PASS")
        else
            log_error "GITHUB" "FAIL - Auth failed: $gh_user"
            test_results+=("GitHub API: FAIL")
            all_passed=false
        fi
    else
        log_error "GITHUB" "SKIP - GITHUB_TOKEN not set"
        test_results+=("GitHub API: SKIP")
        all_passed=false
    fi
    
    # 5. Test GitHub repository access
    log "REPOSITORY" "Testing GitHub Repository Access..."
    if [[ -n "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
        request_spacing 500
        local repo_name
        repo_name=$(github_check_repo "$GITHUB_REPO_AGENTS_WILL_WORK_ON" 2>&1) || true
        if [[ -n "$repo_name" && ! "$repo_name" =~ "ERROR" ]]; then
            log_success "REPOSITORY" "PASS - Accessible: $repo_name"
            test_results+=("GitHub Repo: PASS")
        else
            log_error "REPOSITORY" "FAIL - Cannot access: ${GITHUB_REPO_AGENTS_WILL_WORK_ON}"
            test_results+=("GitHub Repo: FAIL")
            all_passed=false
        fi
    elif [[ -z "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" ]]; then
        log_error "REPOSITORY" "SKIP - GITHUB_REPO_AGENTS_WILL_WORK_ON not set"
        test_results+=("GitHub Repo: SKIP")
        all_passed=false
    else
        log_warning "REPOSITORY" "SKIP - Requires GitHub token"
        test_results+=("GitHub Repo: SKIP")
    fi
    
    # 6. Test Director persona invocation
    log "PERSONA" "Testing Director Persona..."
    if [[ -n "${API_KEY_ANTHROPIC:-}" ]]; then
        request_spacing 500
        local director_prompt="This is a dry run test. Respond with: DRY_RUN_DIRECTOR_OK"
        local director_result
        director_result=$(invoke_persona "director" "$director_prompt" 2>&1) || true
        if echo "$director_result" | grep -qi "DRY_RUN\|OK\|dry\|run"; then
            log_success "PERSONA" "PASS - Director persona responding"
            test_results+=("Director Persona: PASS")
        else
            log_warning "PERSONA" "PARTIAL - Director responded but may need review"
            test_results+=("Director Persona: PARTIAL")
        fi
    else
        log_error "PERSONA" "SKIP - Requires Anthropic API"
        test_results+=("Director Persona: SKIP")
    fi
    
    echo ""
    print_section_header "Dry Run Summary"
    
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"PASS"* ]]; then
            log_success "RESULT" "$result"
        elif [[ "$result" == *"FAIL"* ]]; then
            log_error "RESULT" "$result"
        elif [[ "$result" == *"SKIP"* ]]; then
            log_warning "RESULT" "$result"
        else
            log_neutral "RESULT" "$result"
        fi
    done
    
    echo ""
    
    if [[ "$all_passed" == "true" ]]; then
        log_success "STATUS" "All required integrations passed! Ready for production run."
        log "INFO" "Run './agent.sh run' to execute with the current directive."
    else
        log_warning "STATUS" "Some integrations need attention. Review the results above."
    fi
    
    echo ""
    log "DIRECTIVE" "$directive"
}

cmd_new() {
    clear_current_task
    clear_tmp_dir
    clear_workrepo
    log_success "SESSION" "Cleared. Ready for new directive."
}

# NOTE(jimmylee)
# Displays environment, git, and session state for debugging
cmd_status() {
    print_section_header "WWW-Agent Status"
    
    # Get configured models
    local anthropic_model openai_model
    anthropic_model=$(get_model_by_category "programming" 2>/dev/null) || anthropic_model="claude-opus-4-5"
    openai_model=$(get_model_by_category "human-simulated" 2>/dev/null) || openai_model="gpt-5.2-chat-latest"
    
    log "CONFIG" "Configured models:"
    log "CONFIG" "  Programming/Reasoning: ${anthropic_model}"
    log "CONFIG" "  Human-simulated: ${openai_model}"
    echo ""
    
    log "ENVIRONMENT" "Checking required variables..."
    local missing=()
    [[ -z "${API_KEY_ANTHROPIC:-}" ]] && missing+=("API_KEY_ANTHROPIC")
    [[ -z "${API_KEY_OPEN_AI:-}" ]] && log_warning "OPTIONAL" "API_KEY_OPEN_AI not set"
    [[ -z "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" ]] && log_warning "OPTIONAL" "API_KEY_GOOGLE_CUSTOM_SEARCH not set"
    [[ -z "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]] && log_warning "OPTIONAL" "GOOGLE_CUSTOM_SEARCH_ID not set"
    [[ -z "${GITHUB_TOKEN:-}" ]] && missing+=("GITHUB_TOKEN")
    [[ -z "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" ]] && missing+=("GITHUB_REPO_AGENTS_WILL_WORK_ON")
    [[ -z "${GITHUB_USERNAME:-}" ]] && missing+=("GITHUB_USERNAME")
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "ENVIRONMENT" "All required variables set"
    else
        log_error "ENVIRONMENT" "Missing: ${missing[*]}"
    fi
    echo ""
    
    log "GIT" "Repository status..."
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    log "GIT" "Branch: $branch"
    
    local changes
    changes=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$changes" -gt 0 ]]; then
        log_warning "GIT" "Uncommitted changes: yes ($changes files)"
    else
        log "GIT" "Uncommitted changes: no"
    fi
    echo ""
    
    log "SESSION" "Current session info..."
    local task_id
    task_id=$(get_current_task)
    log "SESSION" "Task ID: ${task_id:-none}"
    
    if [[ -n "$task_id" ]]; then
        local turns_file="${CONTEXT_DIR}/${task_id}/turns.txt"
        local turn_count=0
        [[ -f "$turns_file" ]] && turn_count=$(wc -l < "$turns_file" | tr -d ' ')
        log "SESSION" "Conversation turns: $turn_count"
    fi
    echo ""
}

# NOTE(jimmylee)
# Tests API connections to verify keys are working
cmd_test_models() {
    print_section_header "Testing Model Connections"
    
    source "${AGENT_DIR}/lib/providers.sh"
    
    # Get configured models from config
    local anthropic_model openai_model
    anthropic_model=$(get_model_by_category "programming" 2>/dev/null) || anthropic_model="claude-opus-4-5"
    openai_model=$(get_model_by_category "human-simulated" 2>/dev/null) || openai_model="gpt-5.2-chat-latest"
    
    log "CONFIG" "Model configuration from configs/models.md:"
    log "CONFIG" "  Anthropic: ${anthropic_model}"
    log "CONFIG" "  OpenAI: ${openai_model}"
    echo ""
    
    log "API KEYS" "Checking environment variables..."
    echo ""
    
    if [[ -n "${API_KEY_ANTHROPIC:-}" ]]; then
        log_success "API KEY" "API_KEY_ANTHROPIC: set"
    else
        log_error "API KEY" "API_KEY_ANTHROPIC: not set"
    fi
    
    if [[ -n "${API_KEY_OPEN_AI:-}" ]]; then
        log_success "API KEY" "API_KEY_OPEN_AI: set"
    else
        log_warning "API KEY" "API_KEY_OPEN_AI: not set (optional)"
    fi
    
    if [[ -n "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" && -n "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        log_success "API KEY" "Google Search: configured"
    else
        log_warning "API KEY" "Google Search: not configured (optional)"
    fi
    echo ""
    
    log "TESTING" "Testing API connections..."
    echo ""
    
    # Test Anthropic
    log "ANTHROPIC" "Testing ${anthropic_model}..."
    if [[ -n "${API_KEY_ANTHROPIC:-}" ]]; then
        request_spacing 500
        local result
        result=$(test_anthropic 2>&1) || true
        if [[ "$result" == "PASS" ]]; then
            log_success "ANTHROPIC" "PASS - ${anthropic_model}"
        else
            log_error "ANTHROPIC" "FAIL - $result"
        fi
    else
        log_warning "ANTHROPIC" "SKIP - No API key"
    fi
    
    # Test OpenAI with configured model (gpt-5-2)
    log "OPENAI" "Testing ${openai_model}..."
    if [[ -n "${API_KEY_OPEN_AI:-}" ]]; then
        request_spacing 500
        local result
        result=$(test_openai_gpt5 2>&1) || true
        if [[ "$result" == *"PASS"* ]]; then
            log_success "OPENAI" "$result"
        else
            log_error "OPENAI" "FAIL - $result"
        fi
    else
        log_warning "OPENAI" "SKIP - No API key"
    fi
    
    # Test Google Custom Search
    log "GOOGLE" "Checking Google Custom Search API..."
    if [[ -n "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" && -n "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        request_spacing 500
        local result
        result=$(test_google_search 2>&1) || true
        if [[ "$result" == *"PASS"* ]]; then
            log_success "GOOGLE" "$result"
        else
            log_error "GOOGLE" "FAIL - $result"
        fi
    else
        log_warning "GOOGLE" "SKIP - Not configured"
    fi
    echo ""
}

cmd_clear_context() {
    clear_all_memory
    log_success "CONTEXT" "All context cleared."
}

# Legacy alias
cmd_clear_memory() {
    cmd_clear_context
}

print_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  run             Run agent using .directive file"
    echo "  dry-run         Test full flow without executing changes"
    echo "  new             Clear current session"
    echo "  status          Show environment and session status"
    echo "  test-models     Test API connections only"
    echo "  clear-context   Clear all context and state"
    echo ""
    echo "The agent reads its goal from the .directive file in the repo root."
}

main() {
    local command="${1:-status}"
    shift || true
    
    case "$command" in
        run)
            cmd_run "false"
            ;;
        dry-run)
            cmd_run "true"
            ;;
        new)
            cmd_new
            ;;
        status)
            cmd_status
            ;;
        test-models)
            cmd_test_models
            ;;
        clear-context)
            cmd_clear_context
            ;;
        clear-memory)
            # Legacy alias
            cmd_clear_context
            ;;
        help|--help|-h)
            print_usage
            ;;
        exit)
            exit 0
            ;;
        *)
            log_error "COMMAND" "Unknown command: $command"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
