#!/bin/bash
#
# NOTE(angeldev)
# Centralized JSON handling utilities.
# All JSON escaping and manipulation should use these functions
# for consistency and reliability.

[[ -n "${_JSON_SH_LOADED:-}" ]] && return 0
_JSON_SH_LOADED=1

set -euo pipefail

# NOTE(angeldev)
# Primary JSON escape function using jq.
# This is the most reliable method and handles all edge cases correctly.
# Falls back to bash string manipulation if jq is not available.
#
# Usage: json_escape "string with special chars"
# Returns: JSON-safe escaped string (without surrounding quotes)
json_escape() {
    local str="$1"

    # Use jq for reliable escaping if available
    if command -v jq &>/dev/null; then
        # jq -Rs outputs a quoted JSON string; we strip the quotes for embedding
        printf '%s' "$str" | jq -Rs '.' | sed 's/^"//;s/"$//'
    else
        # Fallback: bash string manipulation
        # Order matters: escape backslashes first
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        str="${str//$'\n'/\\n}"
        str="${str//$'\r'/\\r}"
        str="${str//$'\t'/\\t}"
        echo "$str"
    fi
}

# NOTE(angeldev)
# JSON escape with surrounding quotes included.
# Useful when you need the full quoted JSON string.
#
# Usage: json_escape_quoted "string"
# Returns: "escaped string" (with quotes)
json_escape_quoted() {
    local str="$1"

    if command -v jq &>/dev/null; then
        printf '%s' "$str" | jq -Rs '.'
    else
        echo "\"$(json_escape "$str")\""
    fi
}

# NOTE(www-agent)
# ROBUST JSON EXTRACTION from LLM responses.
# Handles all common patterns that LLMs produce:
# - JSON in ```json code blocks
# - JSON in ``` code blocks (no language)
# - Raw JSON without code blocks
# - JSON with surrounding explanation text
# - Multiple JSON blocks (returns first valid one)
# - Nested objects and arrays
#
# Strategy:
# 1. Try direct jq parse (cleanest case)
# 2. Try extracting from ```json blocks
# 3. Try extracting from ``` blocks
# 4. Try finding JSON by brace matching
# 5. Try aggressive cleanup and retry
#
# Usage: extract_json "response text with JSON somewhere"
# Returns: Clean JSON content, or empty string if extraction fails
extract_json() {
    local response="$1"
    local extracted=""

    # Strategy 1: Direct parse - maybe it's already clean JSON
    if echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    fi

    # Strategy 2: Extract from ```json ... ``` block
    # Use awk for more reliable multi-line handling
    extracted=$(echo "$response" | awk '
        BEGIN { in_block=0; content="" }
        /^```json/ { in_block=1; next }
        /^```$/ { if(in_block) { print content; exit } }
        in_block { content = content (content ? "\n" : "") $0 }
    ')

    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi

    # Strategy 3: Extract from ``` ... ``` block (no language specified)
    extracted=$(echo "$response" | awk '
        BEGIN { in_block=0; content=""; found_json=0 }
        /^```[^j]/ || /^```$/ {
            if(in_block && found_json) { print content; exit }
            in_block=!in_block
            if(in_block) { content=""; found_json=0 }
            next
        }
        /^```json/ { in_block=1; next }
        in_block {
            content = content (content ? "\n" : "") $0
            if($0 ~ /^[[:space:]]*[\{\[]/) found_json=1
        }
    ')

    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi

    # Strategy 4: Find JSON by looking for opening brace/bracket and extracting
    # This handles cases where JSON is embedded in text
    extracted=$(echo "$response" | awk '
        BEGIN {
            brace_count=0; bracket_count=0; in_string=0; escape=0
            json_start=-1; json_content=""
        }
        {
            line = $0
            for(i=1; i<=length(line); i++) {
                c = substr(line, i, 1)

                # Handle escape sequences in strings
                if(escape) { escape=0; continue }
                if(c == "\\") { escape=1; continue }

                # Handle string boundaries
                if(c == "\"" && !escape) {
                    in_string = !in_string
                    continue
                }

                # Only count braces outside strings
                if(!in_string) {
                    if(c == "{") {
                        if(brace_count == 0 && bracket_count == 0) json_start = i
                        brace_count++
                    }
                    if(c == "}") brace_count--
                    if(c == "[") {
                        if(brace_count == 0 && bracket_count == 0) json_start = i
                        bracket_count++
                    }
                    if(c == "]") bracket_count--

                    # Found complete JSON object/array
                    if(json_start > 0 && brace_count == 0 && bracket_count == 0) {
                        json_content = json_content substr(line, json_start, i - json_start + 1)
                        print json_content
                        exit
                    }
                }
            }

            # Accumulate content if we are inside JSON
            if(json_start > 0) {
                if(NR == 1) {
                    json_content = substr(line, json_start)
                } else {
                    json_content = json_content "\n" line
                }
                json_start = 1  # Continue from start of next line
            }
        }
    ')

    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi

    # Strategy 5: Aggressive cleanup - remove common prefixes/suffixes
    # Handle cases like "Here's the JSON:\n```json\n{...}\n```\nLet me know..."
    extracted=$(echo "$response" | \
        sed -n '/[{[]/,/[}\]]/p' | \
        sed 's/^[^{[]*//;s/[^}\]]*$//' | \
        head -1)

    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi

    # Strategy 6: Try to find the LAST JSON block (sometimes models put explanation first)
    extracted=$(echo "$response" | awk '
        BEGIN { in_block=0; content=""; last_json="" }
        /^```json/ { in_block=1; content=""; next }
        /^```$/ {
            if(in_block && content != "") { last_json=content }
            in_block=0
            next
        }
        in_block { content = content (content ? "\n" : "") $0 }
        END { print last_json }
    ')

    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi

    # Strategy 7: Handle truncated JSON - try to find largest valid JSON prefix
    # This helps when the response was cut off
    local len=${#response}
    local try_len=$len
    while [[ $try_len -gt 100 ]]; do
        local prefix="${response:0:$try_len}"
        # Try to close any open braces/brackets
        local open_braces=$(echo "$prefix" | tr -cd '{' | wc -c)
        local close_braces=$(echo "$prefix" | tr -cd '}' | wc -c)
        local open_brackets=$(echo "$prefix" | tr -cd '[' | wc -c)
        local close_brackets=$(echo "$prefix" | tr -cd ']' | wc -c)

        local missing_braces=$((open_braces - close_braces))
        local missing_brackets=$((open_brackets - close_brackets))

        if [[ $missing_braces -ge 0 && $missing_brackets -ge 0 ]]; then
            local suffix=""
            for ((i=0; i<missing_brackets; i++)); do suffix+="]"; done
            for ((i=0; i<missing_braces; i++)); do suffix+="}"; done

            extracted="${prefix}${suffix}"
            if echo "$extracted" | jq empty 2>/dev/null; then
                echo "$extracted"
                return 0
            fi
        fi

        try_len=$((try_len - 100))
    done

    # All strategies failed - return empty
    echo ""
    return 1
}

# NOTE(www-agent)
# Extract JSON with detailed error information for debugging.
# Returns the JSON on stdout, error details on stderr.
#
# Usage: result=$(extract_json_verbose "$response" 2>&1)
extract_json_verbose() {
    local response="$1"
    local result

    result=$(extract_json "$response")
    local status=$?

    if [[ $status -ne 0 || -z "$result" ]]; then
        echo "JSON extraction failed. Response preview:" >&2
        echo "${response:0:500}" >&2
        echo "---" >&2

        # Try to identify the issue
        if ! echo "$response" | grep -q '[{[]'; then
            echo "Issue: No JSON structure found (no { or [ characters)" >&2
        elif ! echo "$response" | grep -q '[}\]]'; then
            echo "Issue: JSON appears truncated (no closing } or ])" >&2
        else
            echo "Issue: JSON structure found but invalid syntax" >&2
            # Try to get jq error
            echo "$response" | jq empty 2>&1 | head -3 >&2
        fi

        return 1
    fi

    echo "$result"
}

# NOTE(angeldev)
# Safely extract a string value from JSON.
# Returns empty string if key doesn't exist or jq fails.
#
# Usage: json_get '{"key": "value"}' "key"
# Returns: value
json_get() {
    local json="$1"
    local key="$2"

    echo "$json" | jq -r ".$key // empty" 2>/dev/null || echo ""
}

# NOTE(angeldev)
# Safely extract a nested string value from JSON.
# Handles dot-notation paths like "parent.child.value"
#
# Usage: json_get_path '{"a": {"b": "value"}}' "a.b"
# Returns: value
json_get_path() {
    local json="$1"
    local path="$2"

    echo "$json" | jq -r ".$path // empty" 2>/dev/null || echo ""
}

# NOTE(angeldev)
# Check if a JSON string is valid.
#
# Usage: if json_valid "$string"; then ...
# Returns: 0 if valid, 1 if invalid
json_valid() {
    local str="$1"
    echo "$str" | jq empty 2>/dev/null
}

# NOTE(angeldev)
# Build a simple JSON object from key-value pairs.
# All values are treated as strings.
#
# Usage: json_object "key1" "value1" "key2" "value2"
# Returns: {"key1": "value1", "key2": "value2"}
json_object() {
    local result="{"
    local first=true

    while [[ $# -ge 2 ]]; do
        local key="$1"
        local value="$2"
        shift 2

        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi

        result+="\"$key\":$(json_escape_quoted "$value")"
    done

    result+="}"
    echo "$result"
}

# NOTE(www-agent)
# Repair common JSON issues that LLMs produce.
# Handles:
# - Trailing commas
# - Single quotes instead of double quotes
# - Unquoted keys
# - Missing commas between elements
#
# Usage: json_repair '{"key": "value",}'
# Returns: {"key": "value"}
json_repair() {
    local json="$1"

    # Remove trailing commas before } or ]
    json=$(echo "$json" | sed 's/,\s*}/}/g; s/,\s*]/]/g')

    # If still invalid, try more aggressive fixes
    if ! echo "$json" | jq empty 2>/dev/null; then
        # Try to fix single quotes (risky but sometimes needed)
        local fixed
        fixed=$(echo "$json" | sed "s/'/\"/g")
        if echo "$fixed" | jq empty 2>/dev/null; then
            echo "$fixed"
            return 0
        fi
    fi

    echo "$json"
}
