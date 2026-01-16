#!/bin/bash
#
# NOTE(jimmylee)
# Configuration loading utilities. Sources environment and loads persona/model configs.

[[ -n "${_CONFIG_SH_LOADED:-}" ]] && return 0
_CONFIG_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

load_env() {
    local env_file="${ROOT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi
}

validate_env() {
    local missing=()

    [[ -z "${API_KEY_ANTHROPIC:-}" ]] && missing+=("API_KEY_ANTHROPIC")
    [[ -z "${GITHUB_TOKEN:-}" ]] && missing+=("GITHUB_TOKEN")
    [[ -z "${GITHUB_REPO_AGENTS_WILL_WORK_ON:-}" ]] && missing+=("GITHUB_REPO_AGENTS_WILL_WORK_ON")
    [[ -z "${GITHUB_USERNAME:-}" ]] && missing+=("GITHUB_USERNAME")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required environment variables:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        return 1
    fi
    return 0
}

validate_api_keys() {
    local missing=()
    
    [[ -z "${API_KEY_ANTHROPIC:-}" ]] && missing+=("API_KEY_ANTHROPIC")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required API keys:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        return 1
    fi
    return 0
}

# NOTE(jimmylee)
# Extracts JSON from markdown code blocks. Used to parse persona configs.
extract_json_from_md() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi
    
    sed -n '/^```json$/,/^```$/p' "$file" | sed '1d;$d'
}

json_get() {
    local json="$1"
    local key="$2"
    
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*: *"\([^"]*\)".*/\1/' | head -1
}

# NOTE(jimmylee)
# Loads model configuration from configs/models.md
# Returns the JSON configuration block
load_model_config() {
    local config_file="${ROOT_DIR}/configs/models.md"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Model config not found: $config_file" >&2
        return 1
    fi
    
    extract_json_from_md "$config_file"
}

# NOTE(jimmylee)
# Gets a model name from config by category (programming, reasoning, human-simulated, research)
get_model_by_category() {
    local category="$1"
    local config
    config=$(load_model_config) || return 1
    
    # Extract the model for the given category
    echo "$config" | tr '\n' ' ' | sed -n "s/.*\"${category}\"[[:space:]]*:[[:space:]]*{[^}]*\"model\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# NOTE(jimmylee)
# Gets the provider for a model category
get_provider_by_category() {
    local category="$1"
    local config
    config=$(load_model_config) || return 1
    
    echo "$config" | tr '\n' ' ' | sed -n "s/.*\"${category}\"[[:space:]]*:[[:space:]]*{[^}]*\"provider\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

load_persona() {
    local persona_name="$1"
    local persona_file="${ROOT_DIR}/personas/${persona_name}.md"
    
    if [[ ! -f "$persona_file" ]]; then
        echo "ERROR: Persona not found: $persona_name" >&2
        return 1
    fi
    
    extract_json_from_md "$persona_file"
}

get_persona_prompt() {
    local persona_name="$1"
    local json
    json=$(load_persona "$persona_name") || return 1
    
    echo "$json" | tr '\n' ' ' | sed 's/.*"system_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's/\\n/\n/g'
}

get_persona_role() {
    local persona_name="$1"
    local json
    json=$(load_persona "$persona_name") || return 1
    json_get "$json" "role"
}

list_personas() {
    for f in "${ROOT_DIR}/personas"/*.md; do
        [[ -f "$f" ]] && basename "$f" .md
    done
}

list_workflows() {
    for f in "${ROOT_DIR}/workflows"/*.md; do
        [[ -f "$f" ]] && basename "$f" .md
    done
}

load_workflow() {
    local workflow_name="$1"
    local workflow_file="${ROOT_DIR}/workflows/${workflow_name}.md"
    
    if [[ ! -f "$workflow_file" ]]; then
        echo "ERROR: Workflow not found: $workflow_name" >&2
        return 1
    fi
    
    cat "$workflow_file"
}

# NOTE(jimmylee)
# Maps personas to their configured models using config file.
# Falls back to defaults if config cannot be read.
get_model_for_persona() {
    local persona_name="$1"
    
    # Determine category based on persona
    local category
    case "$persona_name" in
        director|Director|project-manager|"Project Manager")
            category="reasoning"
            ;;
        engineer|Engineer)
            category="programming"
            ;;
        researcher|Researcher)
            category="research"
            ;;
        technical-writer|"Technical Writer")
            category="human-simulated"
            ;;
        *)
            category="reasoning"
            ;;
    esac
    
    # Try to get from config, fall back to defaults
    local model
    model=$(get_model_by_category "$category" 2>/dev/null)
    
    if [[ -n "$model" ]]; then
        echo "$model"
    else
        # Fallback defaults
        case "$category" in
            programming|reasoning)
                echo "claude-opus-4-5"
                ;;
            research|human-simulated)
                echo "gpt-5.2-chat-latest"
                ;;
            *)
                echo "claude-opus-4-5"
                ;;
        esac
    fi
}

get_provider_for_persona() {
    local persona_name="$1"
    
    # Determine category based on persona
    local category
    case "$persona_name" in
        director|Director|project-manager|"Project Manager")
            category="reasoning"
            ;;
        engineer|Engineer)
            category="programming"
            ;;
        researcher|Researcher)
            category="research"
            ;;
        technical-writer|"Technical Writer")
            category="human-simulated"
            ;;
        *)
            category="reasoning"
            ;;
    esac
    
    # Try to get from config, fall back to defaults
    local provider
    provider=$(get_provider_by_category "$category" 2>/dev/null)
    
    if [[ -n "$provider" ]]; then
        echo "$provider"
    else
        # Fallback defaults
        case "$category" in
            programming|reasoning)
                echo "anthropic"
                ;;
            research|human-simulated)
                echo "openai"
                ;;
            *)
                echo "anthropic"
                ;;
        esac
    fi
}

# NOTE(jimmylee)
# Temp file utilities - uses .tmp directory in repo root instead of system temp.
# This allows easy cleanup between sessions and keeps temp files local.

TMP_DIR="${ROOT_DIR}/.tmp"

# Ensures .tmp directory exists
ensure_tmp_dir() {
    if [[ ! -d "$TMP_DIR" ]]; then
        mkdir -p "$TMP_DIR"
    fi
}

# Creates a temp file in .tmp directory
# Usage: local myfile=$(make_temp_file) or make_temp_file "prefix"
make_temp_file() {
    local prefix="${1:-tmp}"
    ensure_tmp_dir
    local tmpfile="${TMP_DIR}/${prefix}_$(date +%s)_$$_${RANDOM}"
    touch "$tmpfile"
    echo "$tmpfile"
}

# Clears all temp files (call at session start)
clear_tmp_dir() {
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "${TMP_DIR:?}"/*
    fi
    ensure_tmp_dir
}

# NOTE(jimmylee)
# Generates a markdown list of models used for each persona.
# Used for PR transparency to show which models powered each role.
get_model_attribution() {
    local director_model engineer_model researcher_model pm_model writer_model
    director_model=$(get_model_for_persona "director")
    engineer_model=$(get_model_for_persona "engineer")
    researcher_model=$(get_model_for_persona "researcher")
    pm_model=$(get_model_for_persona "project-manager")
    writer_model=$(get_model_for_persona "technical-writer")

    local director_provider engineer_provider researcher_provider pm_provider writer_provider
    director_provider=$(get_provider_for_persona "director")
    engineer_provider=$(get_provider_for_persona "engineer")
    researcher_provider=$(get_provider_for_persona "researcher")
    pm_provider=$(get_provider_for_persona "project-manager")
    writer_provider=$(get_provider_for_persona "technical-writer")

    local attribution="| Skill | Model |
|-------|-------|
| Director skills | ${director_model} (${director_provider}) |
| Engineer skills | ${engineer_model} (${engineer_provider}) |
| Researcher skills | ${researcher_model} (${researcher_provider}) |
| Project Manager skills | ${pm_model} (${pm_provider}) |
| Technical Writer skills | ${writer_model} (${writer_provider}) |
| Web Search | Google Custom Search API |"

    echo "$attribution"
}

export ROOT_DIR
export TMP_DIR
