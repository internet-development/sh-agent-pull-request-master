#!/bin/bash
# NOTE(jimmylee)
# Adapter: Apply targeted edits using Rust tool.
# This is a thin wrapper that ensures the Rust binary is built and delegates to it.
#
# Usage: ./apply-edits.sh apply --file <json_file> --workdir <path>
#    or: echo "<json>" | ./apply-edits.sh apply --stdin --workdir <path>
#    or: ./apply-edits.sh read --file <file_path> --workdir <path>
#
# The Rust tool provides:
# - Multi-line search/replace (fixes AWK line-by-line limitation)
# - Structured JSON error output with closest matches
# - Human-readable progress output
# - File reading with line numbers
#
# For legacy compatibility, this wrapper also handles the old argument format:
#   ./apply-edits.sh --file <json_file> --workdir <path>
#   ./apply-edits.sh --json <json_string> --workdir <path>
#   echo "<json>" | ./apply-edits.sh --stdin --workdir <path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_BINARY="$ROOT_DIR/tools/apply-edits/target/release/apply-edits"

# NOTE(jimmylee)
# Ensure the Rust tool is built.
# This is idempotent - only rebuilds if source has changed.
ensure_rust_tool() {
    if [[ ! -x "$RUST_BINARY" ]]; then
        "$ROOT_DIR/scripts/ensure-tools.sh" || {
            echo "ERROR: Failed to build Rust tools. Is Rust installed?" >&2
            echo "Install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
            exit 1
        }
    fi
}

# NOTE(jimmylee)
# Detect if using old argument format and convert to new format.
# Old format: --file, --json, --stdin as top-level flags
# New format: apply/read subcommand first
convert_legacy_args() {
    local args=("$@")
    local has_subcommand=false
    local new_args=()
    local workdir=""
    local input_mode=""
    local input_value=""
    
    # Check if first arg is a subcommand
    if [[ ${#args[@]} -gt 0 ]]; then
        case "${args[0]}" in
            apply|read|help|--help|-h)
                has_subcommand=true
                ;;
        esac
    fi
    
    if [[ "$has_subcommand" == "true" ]]; then
        # New format - pass through as-is
        echo "${args[@]}"
        return
    fi
    
    # Old format - convert to new format
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
            --workdir)
                workdir="${args[$((i+1))]}"
                ((i+=2))
                ;;
            --file)
                input_mode="--file"
                input_value="${args[$((i+1))]}"
                ((i+=2))
                ;;
            --json)
                # JSON passed as argument - write to temp file
                input_mode="--stdin"
                echo "${args[$((i+1))]}"
                ((i+=2))
                ;;
            --stdin)
                input_mode="--stdin"
                ((i+=1))
                ;;
            *)
                ((i+=1))
                ;;
        esac
    done
    
    # Build new-style command
    echo "apply"
    if [[ -n "$input_mode" ]]; then
        echo "$input_mode"
        if [[ -n "$input_value" ]]; then
            echo "$input_value"
        fi
    fi
    if [[ -n "$workdir" ]]; then
        echo "--workdir"
        echo "$workdir"
    fi
}

# NOTE(jimmylee)
# Main entry point.
main() {
    ensure_rust_tool
    
    # Check if using legacy argument format
    if [[ $# -gt 0 ]]; then
        case "$1" in
            apply|read|help|--help|-h|--version|-V)
                # New format - pass through directly
                exec "$RUST_BINARY" "$@"
                ;;
            --file|--json|--stdin|--workdir)
                # Legacy format - need to handle specially
                
                # Parse legacy args
                local workdir=""
                local input_file=""
                local use_stdin=false
                local json_string=""
                
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --workdir)
                            workdir="$2"
                            shift 2
                            ;;
                        --file)
                            input_file="$2"
                            shift 2
                            ;;
                        --json)
                            json_string="$2"
                            shift 2
                            ;;
                        --stdin)
                            use_stdin=true
                            shift
                            ;;
                        *)
                            shift
                            ;;
                    esac
                done
                
                # Build and execute command
                if [[ -n "$input_file" ]]; then
                    exec "$RUST_BINARY" apply --file "$input_file" --workdir "$workdir"
                elif [[ "$use_stdin" == "true" ]]; then
                    exec "$RUST_BINARY" apply --stdin --workdir "$workdir"
                elif [[ -n "$json_string" ]]; then
                    echo "$json_string" | exec "$RUST_BINARY" apply --stdin --workdir "$workdir"
                else
                    echo "ERROR: No input specified" >&2
                    exit 1
                fi
                ;;
            *)
                # Unknown - try passing through
                exec "$RUST_BINARY" "$@"
                ;;
        esac
    else
        # No args - show help
        exec "$RUST_BINARY" --help
    fi
}

main "$@"
