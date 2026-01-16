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

# NOTE(angeldev)
# Extract JSON from a response that may contain markdown code blocks.
# Commonly needed when parsing LLM responses.
#
# Usage: extract_json "response text with ```json ... ```"
# Returns: Just the JSON content
extract_json() {
    local response="$1"
    
    if echo "$response" | grep -q '```json'; then
        echo "$response" | sed -n '/```json/,/```/p' | sed '1d;$d'
    elif echo "$response" | grep -q '```'; then
        echo "$response" | sed -n '/```/,/```/p' | sed '1d;$d'
    else
        echo "$response"
    fi
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
