#!/bin/bash
#
# NOTE(jimmylee)
# API provider functions using curl. Makes requests to Anthropic, OpenAI, and Google Custom Search.

[[ -n "${_PROVIDERS_SH_LOADED:-}" ]] && return 0
_PROVIDERS_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/constants.sh"
source "${SCRIPT_DIR}/json.sh"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/logging.sh"

# NOTE(angeldev)
# Context window monitoring - track token usage and warn when approaching limits.

# Approximate characters per token (varies by content, but ~4 is a reasonable estimate)
CHARS_PER_TOKEN="${CHARS_PER_TOKEN:-4}"

# Context window limits for different providers (in tokens)
ANTHROPIC_CONTEXT_LIMIT="${ANTHROPIC_CONTEXT_LIMIT:-200000}"
OPENAI_CONTEXT_LIMIT="${OPENAI_CONTEXT_LIMIT:-128000}"

# Warning threshold (percentage of context used before warning)
CONTEXT_WARNING_THRESHOLD="${CONTEXT_WARNING_THRESHOLD:-80}"

# NOTE(angeldev)
# Estimates the token count for a given text.
# Uses a simple character-based heuristic (~4 chars per token).
estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    echo $((char_count / CHARS_PER_TOKEN))
}

# NOTE(angeldev)
# Checks context usage and logs for debugging purposes.
# Returns: 0 always (informational only - we want to use full context)
check_context_usage() {
    local system_prompt="$1"
    local user_message="$2"
    local provider="${3:-anthropic}"

    local system_tokens user_tokens total_tokens
    system_tokens=$(estimate_tokens "$system_prompt")
    user_tokens=$(estimate_tokens "$user_message")
    total_tokens=$((system_tokens + user_tokens + MAX_OUTPUT_TOKENS))

    # Get the appropriate limit
    local context_limit
    case "$provider" in
        anthropic)
            context_limit="$ANTHROPIC_CONTEXT_LIMIT"
            ;;
        openai)
            context_limit="$OPENAI_CONTEXT_LIMIT"
            ;;
        *)
            context_limit="$ANTHROPIC_CONTEXT_LIMIT"
            ;;
    esac

    # Calculate percentage used
    local percent_used=$((total_tokens * 100 / context_limit))

    # Log token estimate for debugging only
    if [[ "${DEBUG_TOKENS:-false}" == "true" ]]; then
        log "TOKENS" "Estimate: ~$total_tokens tokens (${percent_used}% of ${context_limit})"
        log "TOKENS" "  System: ~$system_tokens, User: ~$user_tokens, Reserved output: $MAX_OUTPUT_TOKENS"
    fi

    # Only warn if we're truly over the hard limit
    if [[ $total_tokens -gt $context_limit ]]; then
        log_warning "TOKENS" "Estimated tokens ($total_tokens) exceeds context limit ($context_limit)"
    fi

    return 0
}

# NOTE(angeldev)
# Optional utility: Truncates content to fit within a token budget.
# This is NOT called automatically - only use when explicitly needed.
# Prefer using full context whenever possible.
truncate_to_budget() {
    local content="$1"
    local max_tokens="${2:-150000}"  # Default to generous 150K tokens
    local truncate_marker="${3:-... [content continues]}"

    local current_tokens
    current_tokens=$(estimate_tokens "$content")

    if [[ $current_tokens -le $max_tokens ]]; then
        echo "$content"
        return 0
    fi

    # Only truncate if truly necessary
    local max_chars=$((max_tokens * CHARS_PER_TOKEN))
    local marker_len=${#truncate_marker}
    local truncate_at=$((max_chars - marker_len - 100))

    if [[ $truncate_at -lt 1000 ]]; then
        truncate_at=1000
    fi

    echo "${content:0:$truncate_at}

${truncate_marker}"

    if [[ "${DEBUG_TOKENS:-false}" == "true" ]]; then
        log "TRUNCATE" "Content truncated from ~$current_tokens to ~$max_tokens tokens"
    fi
}

# NOTE(angeldev)
# Gets current session token usage statistics.
# Tracks cumulative input/output tokens across all API calls in session.
SESSION_INPUT_TOKENS=${SESSION_INPUT_TOKENS:-0}
SESSION_OUTPUT_TOKENS=${SESSION_OUTPUT_TOKENS:-0}

track_token_usage() {
    local input_tokens="${1:-0}"
    local output_tokens="${2:-0}"

    SESSION_INPUT_TOKENS=$((SESSION_INPUT_TOKENS + input_tokens))
    SESSION_OUTPUT_TOKENS=$((SESSION_OUTPUT_TOKENS + output_tokens))
    export SESSION_INPUT_TOKENS SESSION_OUTPUT_TOKENS
}

get_session_token_usage() {
    echo "Input: $SESSION_INPUT_TOKENS, Output: $SESSION_OUTPUT_TOKENS, Total: $((SESSION_INPUT_TOKENS + SESSION_OUTPUT_TOKENS))"
}

# NOTE(jimmylee)
# Calls Anthropic Claude API. Default model is claude-opus-4-5.
# Returns: text content on stdout, writes "input_tokens output_tokens" to ANTHROPIC_TOKENS_FILE if set
# Uses temp files to avoid "Argument list too long" errors with large payloads.
call_anthropic() {
    local system_prompt="$1"
    local user_message="$2"
    local max_tokens="${3:-$MAX_OUTPUT_TOKENS}"
    local model="${4:-claude-opus-4-5}"
    
    if [[ -z "${API_KEY_ANTHROPIC:-}" ]]; then
        echo "ERROR: API_KEY_ANTHROPIC not set" >&2
        return 1
    fi
    
    # Create temp files for large content to avoid argument list limits
    local temp_system temp_user temp_payload
    temp_system=$(make_temp_file "anthropic_system")
    temp_user=$(make_temp_file "anthropic_user")
    temp_payload=$(make_temp_file "anthropic_payload")
    
    # Write content to temp files
    printf '%s' "$system_prompt" > "$temp_system"
    printf '%s' "$user_message" > "$temp_user"
    
    # Use jq with --rawfile to read from files instead of command-line args
    # This avoids "Argument list too long" errors with large codebases
    jq -n \
        --arg model "$model" \
        --argjson max_tokens "$max_tokens" \
        --rawfile system "$temp_system" \
        --rawfile user "$temp_user" \
        '{
            model: $model,
            max_tokens: $max_tokens,
            system: $system,
            messages: [
                {role: "user", content: $user}
            ]
        }' > "$temp_payload"
    
    # Clean up input temp files
    rm -f "$temp_system" "$temp_user"
    
    local response
    response=$(curl -s --max-time 600 -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${API_KEY_ANTHROPIC}" \
        -H "anthropic-version: 2023-06-01" \
        -d @"$temp_payload")
    
    # Clean up payload temp file
    rm -f "$temp_payload"
    
    # Check for API errors using jq
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "ERROR: Anthropic API error:" >&2
        echo "$response" | jq -r '.error.message // .error // .' >&2
        return 1
    fi
    
    # Extract token usage if available and write to temp file for caller
    if [[ -n "${ANTHROPIC_TOKENS_FILE:-}" ]]; then
        local input_tokens output_tokens
        input_tokens=$(echo "$response" | jq -r '.usage.input_tokens // 0')
        output_tokens=$(echo "$response" | jq -r '.usage.output_tokens // 0')
        echo "${input_tokens} ${output_tokens}" > "$ANTHROPIC_TOKENS_FILE"
    fi
    
    # Extract text content using jq - handles all escaping correctly
    echo "$response" | jq -r '.content[0].text // empty'
}

call_openai() {
    local system_prompt="$1"
    local user_message="$2"
    local max_tokens="${3:-$MAX_OUTPUT_TOKENS}"
    # Default to gpt-5.2-chat-latest as configured in configs/models.md
    local model="${4:-gpt-5.2-chat-latest}"
    
    if [[ -z "${API_KEY_OPEN_AI:-}" ]]; then
        echo "ERROR: API_KEY_OPEN_AI not set" >&2
        return 1
    fi
    
    # NOTE(jimmylee)
    # GPT-5.x models use max_completion_tokens instead of max_tokens
    local tokens_param="max_tokens"
    if [[ "$model" == gpt-5* ]]; then
        tokens_param="max_completion_tokens"
    fi
    
    # Create temp files for large content to avoid argument list limits
    local temp_system temp_user temp_payload
    temp_system=$(make_temp_file "openai_system")
    temp_user=$(make_temp_file "openai_user")
    temp_payload=$(make_temp_file "openai_payload")
    
    # Write content to temp files
    printf '%s' "$system_prompt" > "$temp_system"
    printf '%s' "$user_message" > "$temp_user"
    
    # Use jq with --rawfile to read from files instead of command-line args
    # This avoids "Argument list too long" errors with large codebases
    jq -n \
        --arg model "$model" \
        --argjson max_tokens "$max_tokens" \
        --arg tokens_param "$tokens_param" \
        --rawfile system "$temp_system" \
        --rawfile user "$temp_user" \
        '{
            model: $model,
            ($tokens_param): $max_tokens,
            messages: [
                {role: "system", content: $system},
                {role: "user", content: $user}
            ]
        }' > "$temp_payload"
    
    # Clean up input temp files
    rm -f "$temp_system" "$temp_user"
    
    local response
    response=$(curl -s --max-time 600 -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY_OPEN_AI}" \
        -d @"$temp_payload")
    
    # Clean up payload temp file
    rm -f "$temp_payload"
    
    # Check for API errors using jq
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "ERROR: OpenAI API error:" >&2
        echo "$response" | jq -r '.error.message // .error // .' >&2
        return 1
    fi
    
    # Extract token usage if available and write to temp file for caller
    if [[ -n "${OPENAI_TOKENS_FILE:-}" ]]; then
        local prompt_tokens completion_tokens
        prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
        completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        echo "${prompt_tokens} ${completion_tokens}" > "$OPENAI_TOKENS_FILE"
    fi
    
    # Extract content using jq - handles all escaping correctly
    echo "$response" | jq -r '.choices[0].message.content // empty'
}

# NOTE(jimmylee)
# Humanizes a structured markdown comment into natural, introspective prose
# for posting to GitHub. Uses GPT-5 to transform the comment while preserving meaning.
# The original comment is logged, and only the humanized version goes to GitHub.
# Accepts optional previous comments to ensure variety in tone and structure.
# Returns: humanized text on stdout, or original comment if API fails
humanize_for_github() {
    local original_comment="$1"
    local previous_comments="${2:-}"
    local personality_file="${AGENT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/.personality"
    
    # Load personality if available
    local personality=""
    if [[ -f "$personality_file" ]]; then
        personality=$(cat "$personality_file")
    else
        personality="A thoughtful, introspective software engineer who cares deeply about code quality."
    fi
    
    # Build previous comments context if available
    local previous_context=""
    if [[ -n "$previous_comments" ]]; then
        previous_context="## Your Previous Comments (this is the conversation so far)

You have already posted these comments as part of your ongoing review. This is ONE cohesive internal monologue:

${previous_comments}

CRITICAL: Your new comment must:
- Continue the conversation naturally, as if you're still thinking through the same review
- Reference or build on insights from your previous comments when relevant (e.g. 'Building on what I noted earlier...' or 'This connects to my earlier observation about...')
- Feel like the next natural thought in your reflection, not a disconnected new review
- Use different sentence structures and openings than previous comments
- Maintain the same voice and tone throughout the conversation
- NOT repeat exact phrases or patterns from above

"
    fi
    
    local system_prompt="You are transforming a structured markdown review comment into natural, human prose.

## Your Personality
${personality}

${previous_context}## Critical Context

The input you receive may contain references to internal review roles like 'Project Manager', 'Technical Writer', 'Researcher', or 'Director'. These are NOT separate people - they are internal labels for different aspects of YOUR OWN review process. You are ONE person who has been reviewing this code from multiple angles.

When the input mentions 'Project Manager feedback' or 'Technical Writer review', translate this to YOUR OWN observations. You noticed scope issues. You noticed naming problems. You caught security concerns. These are all YOUR thoughts.

## Your Task
Convert the markdown into natural prose that reflects genuine self-introspection. You are making your own observations as you talk through your thoughts. This should read like an internal monologue - someone thinking out loud about the code they just reviewed.

## Guidelines
- Write in first person, as yourself reflecting on what you observed
- Use natural language flow, not bullet points or headers
- Sound like you're genuinely working through your thoughts
- Keep the technical substance but make it conversational
- Show your reasoning process, not just conclusions
- Be direct but kind - you care about getting this right
- Vary your sentence structure and length
- Break into 2-3 short paragraphs if the content warrants it (don't force one giant block)
- Each paragraph should flow naturally into the next
- Don't start with 'I think' or 'Looking at' every time
- Avoid robotic phrases like 'upon review' or 'it appears that'
- Keep similar length to the original (not much longer)

## What NOT to do
- NEVER mention 'Project Manager', 'Technical Writer', 'Researcher', 'Director', or any role names
- NEVER say things like 'the Project Manager's feedback' or 'based on the Technical Writer review'
- NEVER reference 'personas', 'angles', 'perspectives', or 'review cycles'
- NEVER hint that multiple people or roles reviewed this - YOU are the only reviewer
- Don't use markdown formatting (no headers, bullets, bold, etc.)
- Don't sound like a template or checklist
- Don't add information that wasn't in the original
- Don't use emojis unless the original had them
- Don't start the same way as any previous comment

Output ONLY the humanized prose (2-3 paragraphs if needed). No preamble, no explanation, just the comment text."

    local user_prompt="Transform this review comment into natural self-introspective prose:

${original_comment}"

    # Use GPT-5 for humanization
    local humanized
    humanized=$(call_openai "$system_prompt" "$user_prompt" 1000 "gpt-5.2-chat-latest" 2>/dev/null) || {
        echo "$original_comment"
        return 0
    }
    
    # If we got an empty response, return original
    if [[ -z "$humanized" ]]; then
        echo "$original_comment"
        return 0
    fi
    
    echo "$humanized"
}

# NOTE(jimmylee)
# Humanizes and shortens a PR title to be concise, natural, and descriptive using GPT-5.
# GitHub PR titles should be under 128 characters while still conveying what the change does.
# This function ALWAYS runs through GPT-5 to ensure titles sound human-written, not robotic.
# Returns: humanized title on stdout, or truncated original if API fails
shorten_pr_title() {
    local original_title="$1"
    local max_length="${2:-128}"

    # NOTE(angeldev): ALWAYS humanize the title, even if short.
    # Short titles can still sound robotic (e.g., "Implement footer component")
    # We want natural-sounding titles like "Add footer to the page"

    local system_prompt="You humanize and improve PR titles to be concise, natural, and clear.

Your job is to make the title sound like a human developer wrote it, not a machine.

Rules:
- Maximum ${max_length} characters
- Start with a natural verb (Add, Fix, Update, Remove, Refactor, Clean up, etc.)
- Sound conversational and natural, not robotic or formal
- No periods at the end
- No prefixes like 'feat:', 'fix:', etc.
- Capture the essence of what changed
- Be specific but brief
- Avoid overly technical jargon when simpler words work

Examples of BAD → GOOD transformations:
- 'Implement footer component for homepage' → 'Add footer to homepage'
- 'Create authentication flow implementation' → 'Add user login'
- 'Implement a new pink theme for the application with proper contrast ratios' → 'Add pink theme'
- 'Fix the bug where users cannot log in when using special characters' → 'Fix login with special chars'
- 'Update navigation component to support mobile responsive design' → 'Make navigation responsive'
- 'Refactor the authentication module to use the new API endpoints' → 'Update auth for new API'
- 'Implement dark mode toggle functionality' → 'Add dark mode toggle'
- 'Create new button component with variants' → 'Add button component'

Notice how the GOOD versions:
- Use simpler verbs (Add vs Implement, Update vs Refactor)
- Sound like something a person would say
- Remove unnecessary words like 'component', 'functionality', 'implementation'

Output ONLY the humanized title. Nothing else."

    local user_prompt="Humanize this PR title to sound natural:\n\n${original_title}"

    local humanized
    # Use GPT-5 for title humanization
    humanized=$(call_openai "$system_prompt" "$user_prompt" 100 "gpt-5.2-chat-latest" 2>/dev/null) || {
        # Fallback: just truncate if API fails
        echo "${original_title:0:$max_length}"
        return 0
    }

    # If empty response, fallback to truncation
    if [[ -z "$humanized" ]]; then
        echo "${original_title:0:$max_length}"
        return 0
    fi

    # Ensure it's not longer than max (LLM might ignore instruction)
    if [[ ${#humanized} -gt $max_length ]]; then
        echo "${humanized:0:$max_length}"
    else
        echo "$humanized"
    fi
}

# NOTE(jimmylee)
# Routes to the appropriate provider based on persona configuration.
# Uses model from config for each persona. Each request is stateless - no conversation
# context is carried between calls. The APIs receive only the current system prompt
# and user message.
call_provider() {
    local persona_name="$1"
    local system_prompt="$2"
    local user_message="$3"

    local provider model
    provider=$(get_provider_for_persona "$persona_name")
    model=$(get_model_for_persona "$persona_name")

    # Get persona icon for display
    local persona_icon
    persona_icon=$(get_persona_style "$persona_name" "icon")

    # Convert persona name to ALLCAPS for display
    local persona_display
    persona_display=$(echo "$persona_name" | tr '[:lower:]' '[:upper:]' | tr '-' ' ')

    # Log that we're starting the API call (simple echo, no animation)
    local spinner_pid
    spinner_pid=$(start_spinner "${persona_icon} ${persona_display} thinking..." "API")

    # Create temp files for token counts
    local tokens_file
    tokens_file=$(make_temp_file "tokens")

    local result
    local actual_provider="$provider"
    local status=0

    case "$provider" in
        anthropic)
            ANTHROPIC_TOKENS_FILE="$tokens_file" result=$(call_anthropic "$system_prompt" "$user_message" "$MAX_OUTPUT_TOKENS" "$model") || status=$?
            ;;
        openai)
            OPENAI_TOKENS_FILE="$tokens_file" result=$(call_openai "$system_prompt" "$user_message" "$MAX_OUTPUT_TOKENS" "$model") || status=$?
            ;;
        *)
            stop_spinner "$spinner_pid"
            log_error "API" "Unknown provider: $provider" >&2
            rm -f "$tokens_file"
            return 1
            ;;
    esac

    # Log completion (no spinner to stop)
    stop_spinner "$spinner_pid"

    if [[ $status -eq 0 && -n "$result" ]]; then
        local bytes=${#result}
        local input_tokens="" output_tokens=""

        # Read token counts from temp file if available
        if [[ -f "$tokens_file" && -s "$tokens_file" ]]; then
            read -r input_tokens output_tokens < "$tokens_file"
        fi

        log_api_complete "$actual_provider" "$bytes" "$input_tokens" "$output_tokens" >&2
    else
        log_error "API" "Failed to get response from ${provider}" >&2
        rm -f "$tokens_file"
        return 1
    fi

    rm -f "$tokens_file"
    echo "$result"
}

# NOTE(jimmylee)
# Calls Google Custom Search API for web research.
# Returns JSON with search results including urls, titles, snippets, and metadata.
# Used by the Researcher persona to verify current facts about packages, APIs, etc.
# Requires: API_KEY_GOOGLE_CUSTOM_SEARCH and GOOGLE_CUSTOM_SEARCH_ID env vars.
#
# Parameters:
#   $1 - query: The search query
#   $2 - num_results: Number of results (1-10, default 10)
#   $3 - date_restrict: Optional date restriction (d=day, w=week, m=month, y=year, e.g., "y1" for past year)
#   $4 - sort: Optional sort order ("date" for date sorting, empty for relevance)
call_google_search() {
    local query="$1"
    local num_results="${2:-10}"
    local date_restrict="${3:-}"
    local sort="${4:-}"
    
    # Validate required environment variables
    if [[ -z "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" ]]; then
        echo "ERROR: API_KEY_GOOGLE_CUSTOM_SEARCH not set" >&2
        return 1
    fi
    
    if [[ -z "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        echo "ERROR: GOOGLE_CUSTOM_SEARCH_ID not set" >&2
        return 1
    fi
    
    # Ensure num_results is between 1 and 10 (Google API limit)
    if [[ "$num_results" -gt 10 ]]; then
        num_results=10
    fi
    if [[ "$num_results" -lt 1 ]]; then
        num_results=1
    fi
    
    # URL-encode the query
    local encoded_query
    encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
    
    # Build the API URL with enhanced parameters
    local api_url="https://www.googleapis.com/customsearch/v1"
    api_url="${api_url}?key=${API_KEY_GOOGLE_CUSTOM_SEARCH}"
    api_url="${api_url}&cx=${GOOGLE_CUSTOM_SEARCH_ID}"
    api_url="${api_url}&q=${encoded_query}"
    api_url="${api_url}&num=${num_results}"
    
    # Add date restriction if specified (e.g., "y1" = past year, "m6" = past 6 months)
    if [[ -n "$date_restrict" ]]; then
        api_url="${api_url}&dateRestrict=${date_restrict}"
    fi
    
    # Add sort by date if specified
    if [[ "$sort" == "date" ]]; then
        api_url="${api_url}&sort=date"
    fi
    
    local response
    response=$(curl -s --max-time 30 -X GET "$api_url")
    
    # Check for empty response
    if [[ -z "$response" ]]; then
        echo "ERROR: Empty response from Google Custom Search API" >&2
        return 1
    fi
    
    # Check for API errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "ERROR: Google Custom Search API error:" >&2
        echo "$response" | jq -r '.error.message // .error // .' >&2
        return 1
    fi
    
    # Return the response (items may be empty if no results)
    echo "$response"
}

test_anthropic() {
    if [[ -z "${API_KEY_ANTHROPIC:-}" ]]; then
        echo "SKIP: API_KEY_ANTHROPIC not set"
        return 1
    fi
    
    local response
    response=$(call_anthropic "You are a test assistant." "Reply with just OK" 10) || return 1
    
    if echo "$response" | grep -qi "ok"; then
        echo "PASS"
        return 0
    else
        echo "FAIL: Unexpected response"
        return 1
    fi
}

test_openai() {
    local model="${1:-gpt-5-2}"
    
    if [[ -z "${API_KEY_OPEN_AI:-}" ]]; then
        echo "SKIP: API_KEY_OPEN_AI not set"
        return 1
    fi
    
    local response
    response=$(call_openai "You are a test assistant." "Reply with just OK" 10 "$model") || return 1
    
    if echo "$response" | grep -qi "ok"; then
        echo "PASS"
        return 0
    else
        echo "FAIL: Unexpected response"
        return 1
    fi
}

# NOTE(jimmylee)
# Tests the gpt-5.2 model specifically as configured in models.md
test_openai_gpt5() {
    if [[ -z "${API_KEY_OPEN_AI:-}" ]]; then
        echo "SKIP: API_KEY_OPEN_AI not set"
        return 1
    fi
    
    # Get the configured model from config
    local configured_model
    configured_model=$(get_model_by_category "human-simulated" 2>/dev/null) || configured_model="gpt-5.2-chat-latest"
    
    # NOTE(jimmylee)
    # GPT-5.x models need more tokens for responses
    local response
    response=$(call_openai "You are a test assistant." "Reply with just OK" 100 "$configured_model") || return 1
    
    if echo "$response" | grep -qi "ok"; then
        echo "PASS (${configured_model})"
        return 0
    else
        echo "FAIL: Unexpected response from ${configured_model}"
        return 1
    fi
}

# NOTE(jimmylee)
# Tests the Google Custom Search API with a simple query
test_google_search() {
    if [[ -z "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" ]]; then
        echo "SKIP: API_KEY_GOOGLE_CUSTOM_SEARCH not set"
        return 1
    fi
    
    if [[ -z "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        echo "SKIP: GOOGLE_CUSTOM_SEARCH_ID not set"
        return 1
    fi
    
    local response
    response=$(call_google_search "test query" 1) || return 1
    
    # Google returns items array (may be empty but response should be valid JSON)
    if echo "$response" | jq -e '.searchInformation' > /dev/null 2>&1; then
        local result_count
        result_count=$(echo "$response" | jq '.items | length // 0')
        echo "PASS (${result_count} results)"
        return 0
    else
        echo "FAIL: Invalid response structure"
        return 1
    fi
}

test_all_providers() {
    echo "Testing Anthropic (claude-opus-4-5)..."
    test_anthropic
    echo ""

    echo "Testing OpenAI (gpt-5-2 from config)..."
    test_openai_gpt5
    echo ""

    echo "Testing Google Custom Search API..."
    test_google_search
    echo ""
}
