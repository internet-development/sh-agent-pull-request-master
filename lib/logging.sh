#!/bin/bash
#
# NOTE(jimmylee)
# Logging utilities with enhanced visual formatting.
# Features: Diamond icon personas, LLM vendor styling, infinite progress bars, token receipts.

[[ -n "${_LOGGING_SH_LOADED:-}" ]] && return 0
_LOGGING_SH_LOADED=1

# Terminal Colors
readonly COLOR_RESET='\033[0m'
readonly COLOR_BLACK='\033[0;30m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[0;37m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_DIM='\033[2m'

# Background Colors
readonly BG_BLACK='\033[40m'
readonly BG_RED='\033[41m'
readonly BG_GREEN='\033[42m'
readonly BG_YELLOW='\033[43m'
readonly BG_BLUE='\033[44m'
readonly BG_MAGENTA='\033[45m'
readonly BG_CYAN='\033[46m'
readonly BG_WHITE='\033[47m'
readonly BG_BRIGHT_BLACK='\033[100m'
readonly BG_BRIGHT_RED='\033[101m'
readonly BG_BRIGHT_GREEN='\033[102m'
readonly BG_BRIGHT_YELLOW='\033[103m'
readonly BG_BRIGHT_BLUE='\033[104m'
readonly BG_BRIGHT_MAGENTA='\033[105m'
readonly BG_BRIGHT_CYAN='\033[106m'
readonly BG_BRIGHT_WHITE='\033[107m'

# Theme presets
readonly THEME_SUCCESS_BG="${BG_GREEN}"
readonly THEME_SUCCESS_FG="${COLOR_BLACK}"
readonly THEME_ERROR_BG="${BG_RED}"
readonly THEME_ERROR_FG="${COLOR_WHITE}"
readonly THEME_NEUTRAL_BG="${BG_WHITE}"
readonly THEME_NEUTRAL_FG="${COLOR_BLACK}"
readonly THEME_INFO_BG="${BG_BLUE}"
readonly THEME_INFO_FG="${COLOR_WHITE}"
readonly THEME_WARNING_BG="${BG_YELLOW}"
readonly THEME_WARNING_FG="${COLOR_BLACK}"

# Directive theme - bright green text for new sessions (no background for terminal compatibility)
readonly THEME_DIRECTIVE_FG="${COLOR_GREEN}${COLOR_BOLD}"

# Persona themes with diamond icons
# All personas use ◆ diamond for consistent visual appearance in logs
readonly PERSONA_DIRECTOR_ICON="◆"
readonly PERSONA_DIRECTOR_BG="${BG_MAGENTA}"
readonly PERSONA_DIRECTOR_FG="${COLOR_WHITE}"

readonly PERSONA_PROJECT_MANAGER_ICON="◆"
readonly PERSONA_PROJECT_MANAGER_BG="${BG_CYAN}"
readonly PERSONA_PROJECT_MANAGER_FG="${COLOR_BLACK}"

readonly PERSONA_ENGINEER_ICON="◆"
readonly PERSONA_ENGINEER_BG="${BG_GREEN}"
readonly PERSONA_ENGINEER_FG="${COLOR_BLACK}"

readonly PERSONA_RESEARCHER_ICON="◆"
readonly PERSONA_RESEARCHER_BG="${BG_BLUE}"
readonly PERSONA_RESEARCHER_FG="${COLOR_WHITE}"

readonly PERSONA_TECHNICAL_WRITER_ICON="◆"
readonly PERSONA_TECHNICAL_WRITER_BG="${BG_YELLOW}"
readonly PERSONA_TECHNICAL_WRITER_FG="${COLOR_BLACK}"

# LLM Vendor themes with diamond icon
readonly LLM_ICON="◆"
readonly VENDOR_ANTHROPIC_BG="${BG_BRIGHT_RED}"
readonly VENDOR_ANTHROPIC_FG="${COLOR_WHITE}"

readonly VENDOR_OPENAI_BG="${BG_BRIGHT_GREEN}"
readonly VENDOR_OPENAI_FG="${COLOR_BLACK}"

readonly VENDOR_GOOGLE_BG="${BG_BRIGHT_BLUE}"
readonly VENDOR_GOOGLE_FG="${COLOR_WHITE}"

readonly VENDOR_LOCAL_BG="${BG_BRIGHT_MAGENTA}"
readonly VENDOR_LOCAL_FG="${COLOR_WHITE}"

# Stage width for consistent formatting
readonly STAGE_WIDTH=20

# Request spacing configuration (milliseconds)
REQUEST_DELAY_MS="${REQUEST_DELAY_MS:-1000}"

# Simple status indicators (no animation)
readonly STATUS_WORKING="..."
readonly STATUS_DONE="OK"
readonly STATUS_ERROR="ERROR"

# NOTE(jimmylee)
# Applies color to text and resets after
color_text() {
    local text="$1"
    local color="$2"
    echo -e "${color}${text}${COLOR_RESET}"
}

# NOTE(jimmylee)
# Gets persona styling (icon, bg, fg) by name
get_persona_style() {
    local persona="$1"
    local style_type="$2"  # icon, bg, or fg
    
    case "$persona" in
        director|Director)
            case "$style_type" in
                icon) echo "$PERSONA_DIRECTOR_ICON" ;;
                bg) echo "$PERSONA_DIRECTOR_BG" ;;
                fg) echo "$PERSONA_DIRECTOR_FG" ;;
            esac
            ;;
        project-manager|"Project Manager"|project_manager)
            case "$style_type" in
                icon) echo "$PERSONA_PROJECT_MANAGER_ICON" ;;
                bg) echo "$PERSONA_PROJECT_MANAGER_BG" ;;
                fg) echo "$PERSONA_PROJECT_MANAGER_FG" ;;
            esac
            ;;
        engineer|Engineer)
            case "$style_type" in
                icon) echo "$PERSONA_ENGINEER_ICON" ;;
                bg) echo "$PERSONA_ENGINEER_BG" ;;
                fg) echo "$PERSONA_ENGINEER_FG" ;;
            esac
            ;;
        researcher|Researcher)
            case "$style_type" in
                icon) echo "$PERSONA_RESEARCHER_ICON" ;;
                bg) echo "$PERSONA_RESEARCHER_BG" ;;
                fg) echo "$PERSONA_RESEARCHER_FG" ;;
            esac
            ;;
        technical-writer|"Technical Writer"|technical_writer)
            case "$style_type" in
                icon) echo "$PERSONA_TECHNICAL_WRITER_ICON" ;;
                bg) echo "$PERSONA_TECHNICAL_WRITER_BG" ;;
                fg) echo "$PERSONA_TECHNICAL_WRITER_FG" ;;
            esac
            ;;
        *)
            case "$style_type" in
                icon) echo "●" ;;
                bg) echo "$BG_WHITE" ;;
                fg) echo "$COLOR_BLACK" ;;
            esac
            ;;
    esac
}

# NOTE(jimmylee)
# Gets LLM vendor styling by name
get_vendor_style() {
    local vendor="$1"
    local style_type="$2"  # bg or fg
    
    case "$vendor" in
        anthropic|Anthropic|ANTHROPIC)
            case "$style_type" in
                bg) echo "$VENDOR_ANTHROPIC_BG" ;;
                fg) echo "$VENDOR_ANTHROPIC_FG" ;;
            esac
            ;;
        openai|OpenAI|OPENAI)
            case "$style_type" in
                bg) echo "$VENDOR_OPENAI_BG" ;;
                fg) echo "$VENDOR_OPENAI_FG" ;;
            esac
            ;;
        google|Google|GOOGLE)
            case "$style_type" in
                bg) echo "$VENDOR_GOOGLE_BG" ;;
                fg) echo "$VENDOR_GOOGLE_FG" ;;
            esac
            ;;
        local|Local|LOCAL)
            case "$style_type" in
                bg) echo "$VENDOR_LOCAL_BG" ;;
                fg) echo "$VENDOR_LOCAL_FG" ;;
            esac
            ;;
        *)
            case "$style_type" in
                bg) echo "$BG_WHITE" ;;
                fg) echo "$COLOR_BLACK" ;;
            esac
            ;;
    esac
}

# NOTE(jimmylee)
# Main logging function with enhanced formatting.
# Usage: log "STAGE" "message" ["success"|"error"|"warning"|"info"]
log() {
    local stage="$1"
    local message="$2"
    local theme="${3:-info}"
    
    local bg_color fg_color
    
    case "$theme" in
        success)
            bg_color="$THEME_SUCCESS_BG"
            fg_color="$THEME_SUCCESS_FG"
            ;;
        error)
            bg_color="$THEME_ERROR_BG"
            fg_color="$THEME_ERROR_FG"
            ;;
        warning)
            bg_color="$THEME_WARNING_BG"
            fg_color="$THEME_WARNING_FG"
            ;;
        neutral)
            bg_color="$THEME_NEUTRAL_BG"
            fg_color="$THEME_NEUTRAL_FG"
            ;;
        directive)
            bg_color=""
            fg_color="$THEME_DIRECTIVE_FG"
            ;;
        *)
            bg_color="$THEME_INFO_BG"
            fg_color="$THEME_INFO_FG"
            ;;
    esac
    
    # Pad stage to fixed width
    local padded_stage
    padded_stage=$(printf "%-${STAGE_WIDTH}s" "$stage")
    
    # Format stage with colors
    local formatted_stage
    formatted_stage="${bg_color}${fg_color}${padded_stage}${COLOR_RESET}"
    
    # Handle multi-line messages
    local first_line=true
    while IFS= read -r line; do
        if [[ "$first_line" == "true" ]]; then
            echo -e "${formatted_stage} ${line}"
            first_line=false
        else
            printf "%${STAGE_WIDTH}s %s\n" "" "$line"
        fi
    done <<< "$message"
}

# NOTE(jimmylee)
# Logs a directive with green text styling
log_directive() {
    local message="$1"
    
    echo ""
    echo -e "${THEME_DIRECTIVE_FG}████████████████████████████████████████████████████████████████${COLOR_RESET}"
    echo -e "${THEME_DIRECTIVE_FG}★ NEW SESSION${COLOR_RESET}"
    echo -e "${THEME_DIRECTIVE_FG}████████████████████████████████████████████████████████████████${COLOR_RESET}"
    echo ""
    echo -e "${THEME_DIRECTIVE_FG}DIRECTIVE${COLOR_RESET}  $message"
    echo ""
}

# NOTE(jimmylee)
# Logs a persona with diamond icon and green text (matching directive style)
log_persona() {
    local persona="$1"
    local message="$2"
    local theme="${3:-info}"
    
    local icon
    icon=$(get_persona_style "$persona" "icon")
    
    local persona_upper
    persona_upper=$(echo "$persona" | tr '[:lower:]' '[:upper:]' | tr '-' ' ')
    
    # Account for Unicode diamond taking 1 extra display column
    local label="${icon} ${persona_upper}"
    local pad_width=$((STAGE_WIDTH - 1))
    local padded_stage
    padded_stage=$(printf "%-${pad_width}s" "$label")
    
    # Use green text like the directive log for consistent persona styling
    local formatted_stage
    formatted_stage="${THEME_DIRECTIVE_FG}${padded_stage}${COLOR_RESET}"
    
    echo -e "${formatted_stage} ${message}"
}

# NOTE(jimmylee)
# Logs an LLM vendor API call with diamond icon and colored background
log_vendor() {
    local vendor="$1"
    local model="$2"
    local message="$3"
    
    local bg fg
    bg=$(get_vendor_style "$vendor" "bg")
    fg=$(get_vendor_style "$vendor" "fg")
    
    local vendor_upper
    vendor_upper=$(echo "$vendor" | tr '[:lower:]' '[:upper:]')
    
    # Account for Unicode diamond taking 1 extra display column
    local label="${LLM_ICON} ${vendor_upper}"
    local pad_width=$((STAGE_WIDTH - 1))
    local padded_stage
    padded_stage=$(printf "%-${pad_width}s" "$label")
    
    local formatted_stage
    formatted_stage="${bg}${fg}${padded_stage}${COLOR_RESET}"
    
    if [[ -n "$model" ]]; then
        echo -e "${formatted_stage} ${message} ${COLOR_DIM}(${model})${COLOR_RESET}"
    else
        echo -e "${formatted_stage} ${message}"
    fi
}

# NOTE(jimmylee)
# Logs API response with bytes and token info
log_api_receipt() {
    local vendor="$1"
    local bytes="$2"
    local input_tokens="${3:-}"
    local output_tokens="${4:-}"
    
    local bg fg
    bg=$(get_vendor_style "$vendor" "bg")
    fg=$(get_vendor_style "$vendor" "fg")
    
    local vendor_upper
    vendor_upper=$(echo "$vendor" | tr '[:lower:]' '[:upper:]')
    
    # Account for Unicode diamond taking 1 extra display column
    local label="${LLM_ICON} ${vendor_upper}"
    local pad_width=$((STAGE_WIDTH - 1))
    local padded_stage
    padded_stage=$(printf "%-${pad_width}s" "$label")
    
    local formatted_stage
    formatted_stage="${bg}${fg}${padded_stage}${COLOR_RESET}"
    
    local receipt="Response: ${bytes} bytes"
    if [[ -n "$input_tokens" && -n "$output_tokens" ]]; then
        receipt="${receipt} │ Tokens: ${input_tokens} in → ${output_tokens} out"
    fi
    
    echo -e "${formatted_stage} ${COLOR_DIM}${receipt}${COLOR_RESET}"
}

# NOTE(jimmylee)
# Shorthand logging functions
log_success() {
    log "$1" "$2" "success"
}

log_error() {
    log "$1" "$2" "error"
}

log_warning() {
    log "$1" "$2" "warning"
}

log_info() {
    log "$1" "$2" "info"
}

log_neutral() {
    log "$1" "$2" "neutral"
}

# NOTE(jimmylee)
# Simple log for API start (no spinner to avoid subshell issues)
log_api_start() {
    local vendor="$1"
    local model="$2"
    local persona="$3"
    
    local bg fg
    bg=$(get_vendor_style "$vendor" "bg")
    fg=$(get_vendor_style "$vendor" "fg")
    
    local vendor_upper
    vendor_upper=$(echo "$vendor" | tr '[:lower:]' '[:upper:]')
    
    # Account for Unicode diamond taking 1 extra display column
    local label="${LLM_ICON} ${vendor_upper}"
    local pad_width=$((STAGE_WIDTH - 1))
    local padded_stage
    padded_stage=$(printf "%-${pad_width}s" "$label")
    
    local formatted_stage
    formatted_stage="${bg}${fg}${padded_stage}${COLOR_RESET}"
    
    local persona_icon
    persona_icon=$(get_persona_style "$persona" "icon")
    
    local persona_upper
    persona_upper=$(echo "$persona" | tr '[:lower:]' '[:upper:]' | tr '-' ' ')
    
    # Persona name in green like directive
    echo -e "${formatted_stage} Calling ${model} for ${THEME_DIRECTIVE_FG}${persona_icon} ${persona_upper}${COLOR_RESET}..."
}

# NOTE(jimmylee)
# Log API completion with receipt
log_api_complete() {
    local vendor="$1"
    local bytes="$2"
    local input_tokens="${3:-}"
    local output_tokens="${4:-}"
    
    local bg fg
    bg=$(get_vendor_style "$vendor" "bg")
    fg=$(get_vendor_style "$vendor" "fg")
    
    local vendor_upper
    vendor_upper=$(echo "$vendor" | tr '[:lower:]' '[:upper:]')
    
    # Account for Unicode diamond taking 1 extra display column
    local label="${LLM_ICON} ${vendor_upper}"
    local pad_width=$((STAGE_WIDTH - 1))
    local padded_stage
    padded_stage=$(printf "%-${pad_width}s" "$label")
    
    local formatted_stage
    formatted_stage="${bg}${fg}${padded_stage}${COLOR_RESET}"
    
    local receipt="✓ Response: ${bytes} bytes"
    if [[ -n "$input_tokens" && -n "$output_tokens" ]]; then
        receipt="${receipt} │ Tokens: ${input_tokens} in → ${output_tokens} out"
    fi
    
    echo -e "${formatted_stage} ${receipt}"
}

# NOTE(jimmylee)
# Simple delay without animation - just sleeps for the specified time
delay_with_progress() {
    local delay_ms="$1"
    local stage="$2"
    local message="$3"
    
    # Just sleep, no animation
    local delay_sec
    delay_sec=$(echo "scale=3; $delay_ms / 1000" | bc 2>/dev/null || echo "1")
    sleep "$delay_sec"
}

# NOTE(jimmylee)
# Adds delay between API requests to prevent rate limiting.
request_spacing() {
    local delay_ms="${1:-$REQUEST_DELAY_MS}"
    local delay_sec
    delay_sec=$(echo "scale=3; $delay_ms / 1000" | bc 2>/dev/null || echo "1")
    sleep "$delay_sec"
}

# NOTE(jimmylee)
# Adds delay between requests (no animation).
request_spacing_with_progress() {
    local delay_ms="${1:-$REQUEST_DELAY_MS}"
    local message="${2:-}"
    
    # Just use request_spacing, no visual feedback needed
    request_spacing "$delay_ms"
}

# NOTE(jimmylee)
# Prints a section header with block formatting matching the directive style.
# Use this for major section breaks (e.g., "Offline Mode Setup", "Testing Model Connections")
print_section_header() {
    local title="$1"
    echo ""
    echo -e "${THEME_DIRECTIVE_FG}████████████████████████████████████████████████████████████████${COLOR_RESET}"
    echo -e "${THEME_DIRECTIVE_FG}★ ${title}${COLOR_RESET}"
    echo -e "${THEME_DIRECTIVE_FG}████████████████████████████████████████████████████████████████${COLOR_RESET}"
    echo ""
}

# NOTE(jimmylee)
# Prints a phase header for workflow stages.
# Use this for workflow phases (e.g., "PLANNING", "IMPLEMENTATION", "COMPLETE")
log_phase() {
    local phase_name="$1"
    echo ""
    log "PHASE" "██████████████████████████████████████████"
    log "PHASE" "$phase_name"
    log "PHASE" "██████████████████████████████████████████"
    echo ""
}

# NOTE(jimmylee)
# Prints a subsection header for grouping related output.
# Use this for smaller sections within adapters (e.g., "SUMMARY", "GIT STATUS")
log_subsection() {
    local title="$1"
    echo ""
    echo "██████████████████████████████████████████"
    echo "$title"
    echo "██████████████████████████████████████████"
}

# NOTE(jimmylee)
# Prints JSON data in a formatted way for logs
log_json() {
    local stage="$1"
    local json_data="$2"
    local theme="${3:-info}"
    
    local formatted_json
    if command -v jq &>/dev/null; then
        formatted_json=$(echo "$json_data" | jq '.' 2>/dev/null || echo "$json_data")
    else
        formatted_json="$json_data"
    fi
    
    log "$stage" "$formatted_json" "$theme"
}

# NOTE(jimmylee)
# Simple start message - no animation, just echoes the message.
# Returns a dummy PID (0) for API compatibility.
# Usage: spinner_pid=$(start_spinner "Loading..."); do_work; stop_spinner $spinner_pid
start_spinner() {
    local message="$1"
    local stage="${2:-WORKING}"  # Kept for compatibility
    
    # Simple echo-based output - no animation
    echo -e "${COLOR_CYAN}${STATUS_WORKING}${COLOR_RESET} ${message}" >&2
    
    # Return dummy PID for compatibility
    echo "0"
}

# NOTE(jimmylee)
# Simple stop message - no animation cleanup needed.
stop_spinner() {
    local pid="$1"
    local final_message="${2:-}"
    local stage="${3:-}"
    local status="${4:-success}"
    
    # No cleanup needed since we don't use background processes
    
    # Print final message if provided
    if [[ -n "$final_message" && -n "$stage" ]]; then
        case "$status" in
            success) log_success "$stage" "$final_message" ;;
            error) log_error "$stage" "$final_message" ;;
            warning) log_warning "$stage" "$final_message" ;;
            *) log "$stage" "$final_message" ;;
        esac
    fi
}

# NOTE(jimmylee)
# Runs a command with simple logging. No animation.
# Usage: output=$(run_with_spinner "message" "stage" command args...)
run_with_spinner() {
    local message="$1"
    local stage="$2"
    shift 2
    
    # Simple echo-based output
    echo -e "${COLOR_CYAN}${STATUS_WORKING}${COLOR_RESET} ${message}" >&2
    
    local output
    local exit_code
    output=$("$@" 2>&1) && exit_code=0 || exit_code=$?
    
    echo "$output"
    return $exit_code
}

# NOTE(jimmylee)
# Prints a status message (simple echo, no line overwriting)
print_status() {
    local stage="$1"
    local message="$2"
    local icon="${3:-●}"
    
    # Simple echo to stderr
    echo -e "${COLOR_CYAN}${icon}${COLOR_RESET} ${message}" >&2
}

# NOTE(jimmylee)
# Prints a status completion message
print_status_done() {
    local stage="$1"
    local message="$2"
    local theme="${3:-success}"
    
    case "$theme" in
        success) log_success "$stage" "$message" ;;
        error) log_error "$stage" "$message" ;;
        warning) log_warning "$stage" "$message" ;;
        *) log "$stage" "$message" ;;
    esac
}

# =============================================================================
# UNIVERSAL PERSONA OUTPUT FORMAT
# =============================================================================
# All persona responses should be formatted consistently for interop.
# Format: JSON with standardized fields that can be parsed by any consumer.

# NOTE(jimmylee)
# Formats a persona response into the universal output structure.
# This creates a consistent JSON format that can be parsed by other systems.
# 
# Fields:
#   persona: Name of the persona that generated the response
#   timestamp: ISO 8601 timestamp
#   type: Type of output (plan|implementation|review|input|synthesis)
#   content: The actual response content (can be JSON or text)
#   metadata: Optional additional context
#
# Usage: format_persona_output "director" "plan" "$response" "$metadata"
format_persona_output() {
    local persona="$1"
    local output_type="$2"
    local content="$3"
    local metadata="${4:-}"
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local icon
    icon=$(get_persona_style "$persona" "icon")
    
    # Build the JSON output
    local output
    if [[ -n "$metadata" ]]; then
        output=$(jq -n \
            --arg persona "$persona" \
            --arg icon "$icon" \
            --arg timestamp "$timestamp" \
            --arg type "$output_type" \
            --arg content "$content" \
            --argjson metadata "$metadata" \
            '{
                persona: $persona,
                icon: $icon,
                timestamp: $timestamp,
                type: $type,
                content: $content,
                metadata: $metadata
            }' 2>/dev/null)
    else
        output=$(jq -n \
            --arg persona "$persona" \
            --arg icon "$icon" \
            --arg timestamp "$timestamp" \
            --arg type "$output_type" \
            --arg content "$content" \
            '{
                persona: $persona,
                icon: $icon,
                timestamp: $timestamp,
                type: $type,
                content: $content
            }' 2>/dev/null)
    fi
    
    # Fallback if jq fails
    if [[ -z "$output" ]]; then
        output="{\"persona\":\"${persona}\",\"icon\":\"${icon}\",\"timestamp\":\"${timestamp}\",\"type\":\"${output_type}\",\"content\":\"(content too large for inline JSON)\"}"
    fi
    
    echo "$output"
}

# NOTE(jimmylee)
# Parses a universal persona output and extracts a specific field.
# Usage: parse_persona_output "$output" "content"
parse_persona_output() {
    local output="$1"
    local field="$2"
    
    echo "$output" | jq -r ".$field // empty" 2>/dev/null
}

# NOTE(jimmylee)
# Logs a persona output in a human-readable format while preserving the structured data.
# This is used for terminal display while keeping the data parseable.
log_persona_output() {
    local persona="$1"
    local output_type="$2"
    local summary="$3"
    
    local icon
    icon=$(get_persona_style "$persona" "icon")
    
    local persona_upper
    persona_upper=$(echo "$persona" | tr '[:lower:]' '[:upper:]' | tr '-' ' ')
    
    local type_upper
    type_upper=$(echo "$output_type" | tr '[:lower:]' '[:upper:]')
    
    # Format: [PERSONA ICON NAME] [TYPE] summary - green text like directive
    local label="${icon} ${persona_upper}"
    local pad_width=$((STAGE_WIDTH - 1))
    local padded_stage
    padded_stage=$(printf "%-${pad_width}s" "$label")
    
    echo -e "${THEME_DIRECTIVE_FG}${padded_stage}${COLOR_RESET} ${COLOR_DIM}[${type_upper}]${COLOR_RESET} ${summary}"
}

# =============================================================================
# TERMINAL SAFETY & CLEANUP
# =============================================================================
# Simplified cleanup - no background processes to track

# NOTE(jimmylee)
# No-op functions for backward compatibility
_register_spinner() {
    : # No-op - no background spinners to track
}

_unregister_spinner() {
    : # No-op - no background spinners to track
}

# NOTE(jimmylee)
# Simple terminal cleanup (no spinners to kill)
_cleanup_terminal() {
    # Just ensure terminal is in a good state
    stty sane 2>/dev/null || true
}

# NOTE(jimmylee)
# Graceful shutdown handler - simple version without spinner cleanup
setup_shutdown_handler() {
    trap 'echo "" >&2; log "SHUTDOWN" "Interrupted (Ctrl+C)" "warning"; exit 130' SIGINT
    trap 'log "SHUTDOWN" "Terminated" "warning"; exit 143' SIGTERM
}
