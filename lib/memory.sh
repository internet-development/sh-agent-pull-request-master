#!/bin/bash
#
# NOTE(jimmylee)
# Task context and state management. All state stored as text files under .context/ and .state/.

[[ -n "${_MEMORY_SH_LOADED:-}" ]] && return 0
_MEMORY_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

CONTEXT_DIR="${ROOT_DIR}/.context"
STATE_DIR="${ROOT_DIR}/.state"

# Legacy alias for backwards compatibility
MEMORY_DIR="${CONTEXT_DIR}"

# NOTE(jimmylee)
# Flushes all context from previous sessions. Called at the start of each new session.
flush_context() {
    find "${CONTEXT_DIR}" -mindepth 1 -not -name '.gitkeep' -delete 2>/dev/null || true
    find "${STATE_DIR}" -mindepth 1 -not -name '.gitkeep' -delete 2>/dev/null || true
    mkdir -p "${CONTEXT_DIR}" "${STATE_DIR}"
}

init_task() {
    local task_id="${1:-task-$(date +%s)}"
    local task_dir="${CONTEXT_DIR}/${task_id}"
    
    mkdir -p "$task_dir"
    
    cat > "${task_dir}/meta.txt" <<EOF
task_id=${task_id}
created=$(date -Iseconds)
status=active
EOF
    
    echo "# Task Log: ${task_id}" > "${task_dir}/log.md"
    echo "" >> "${task_dir}/log.md"
    echo "Created: $(date)" >> "${task_dir}/log.md"
    echo "" >> "${task_dir}/log.md"
    
    echo "$task_id" > "${STATE_DIR}/current_task"
    
    echo "$task_id"
}

get_current_task() {
    local current_file="${STATE_DIR}/current_task"
    if [[ -f "$current_file" ]]; then
        cat "$current_file"
    else
        echo ""
    fi
}

# NOTE(jimmylee)
# Appends an entry to the task's markdown log for auditability.
log_entry() {
    local entry_type="$1"
    local persona="$2"
    local content="$3"
    
    local task_id
    task_id=$(get_current_task)
    
    if [[ -z "$task_id" ]]; then
        echo "ERROR: No active task" >&2
        return 1
    fi
    
    local log_file="${CONTEXT_DIR}/${task_id}/log.md"
    
    # Use tr for uppercase conversion (compatible with bash 3.2 on macOS)
    local entry_type_upper
    entry_type_upper=$(echo "$entry_type" | tr '[:lower:]' '[:upper:]')
    
    local persona_tag=""
    if [[ -n "$persona" ]]; then
        persona_tag=" [$persona]"
    fi
    
    cat >> "$log_file" <<EOF

---

## ${entry_type_upper}${persona_tag}

**Time:** $(date -Iseconds)

${content}

EOF
}

# NOTE(jimmylee)
# Saves conversation turns as separate files and indexes them.
# Enables conversation history replay.
save_turn() {
    local persona="$1"
    local prompt="$2"
    local response="$3"
    
    local task_id
    task_id=$(get_current_task)
    
    if [[ -z "$task_id" ]]; then
        echo "ERROR: No active task" >&2
        return 1
    fi
    
    local turns_file="${CONTEXT_DIR}/${task_id}/turns.txt"
    local turn_num=1
    
    if [[ -f "$turns_file" ]]; then
        turn_num=$(($(wc -l < "$turns_file") / 4 + 1))
    fi
    
    local prompt_file="${CONTEXT_DIR}/${task_id}/turn_${turn_num}_prompt.txt"
    local response_file="${CONTEXT_DIR}/${task_id}/turn_${turn_num}_response.txt"
    
    echo "$prompt" > "$prompt_file"
    echo "$response" > "$response_file"
    
    echo "${turn_num}|${persona}|${prompt_file}|${response_file}" >> "$turns_file"
    
    log_entry "conversation" "$persona" "**Prompt:**
\`\`\`
${prompt}
\`\`\`

**Response:**
\`\`\`
${response}
\`\`\`"
}

get_history() {
    local task_id
    task_id=$(get_current_task)
    
    if [[ -z "$task_id" ]]; then
        return
    fi
    
    local turns_file="${CONTEXT_DIR}/${task_id}/turns.txt"
    
    if [[ ! -f "$turns_file" ]]; then
        return
    fi
    
    while IFS='|' read -r num persona prompt_file response_file; do
        if [[ -f "$prompt_file" && -f "$response_file" ]]; then
            echo "user|$(cat "$prompt_file")"
            echo "assistant|$(cat "$response_file")"
        fi
    done < "$turns_file"
}

clear_current_task() {
    rm -f "${STATE_DIR}/current_task"
    echo "Session cleared"
}

clear_task() {
    local task_id="$1"
    local task_dir="${CONTEXT_DIR}/${task_id}"
    
    if [[ -d "$task_dir" ]]; then
        rm -rf "$task_dir"
        echo "Cleared task: $task_id"
    fi
    
    if [[ "$(get_current_task)" == "$task_id" ]]; then
        clear_current_task
    fi
}

clear_all_memory() {
    flush_context
    echo "All context cleared"
}

list_tasks() {
    for dir in "${CONTEXT_DIR}"/*/; do
        if [[ -d "$dir" ]]; then
            basename "$dir"
        fi
    done 2>/dev/null || true
}

# NOTE(jimmylee)
# Saves insights for later promotion to workflows/adapters/personas.
save_insight() {
    local insight_type="$1"
    local target="$2"
    local suggestion="$3"
    local context="$4"
    
    local task_id
    task_id=$(get_current_task)
    
    if [[ -z "$task_id" ]]; then
        task_id="global"
        mkdir -p "${CONTEXT_DIR}/${task_id}"
    fi
    
    local insights_file="${CONTEXT_DIR}/${task_id}/insights.md"
    
    # Use tr for uppercase conversion (compatible with bash 3.2 on macOS)
    local insight_type_upper
    insight_type_upper=$(echo "$insight_type" | tr '[:lower:]' '[:upper:]')
    
    cat >> "$insights_file" <<EOF

## ${insight_type_upper} Improvement

**Target:** ${target}
**Time:** $(date -Iseconds)

**Context:**
${context}

**Suggestion:**
${suggestion}

---

EOF
}

mkdir -p "$STATE_DIR" "$CONTEXT_DIR"

export CONTEXT_DIR
