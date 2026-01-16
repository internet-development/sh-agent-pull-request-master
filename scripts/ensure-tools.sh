#!/bin/bash
# NOTE(jimmylee)
# Ensures Rust tools are compiled before agent runs.
# Called automatically on agent startup.
# This script is idempotent - it only rebuilds when source changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/tools"

# NOTE(jimmylee)
# Color codes for output formatting.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${CYAN}[BUILD]${NC} $1"; }

# NOTE(jimmylee)
# Check if Rust/Cargo is available on the system.
# Provides installation instructions if not found.
check_rust() {
    if command -v cargo &> /dev/null; then
        return 0
    fi
    
    log_error "Rust/Cargo not found."
    log_error ""
    log_error "Please install Rust using rustup:"
    log_error "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    log_error ""
    log_error "Then restart your terminal and run the agent again."
    return 1
}

# NOTE(jimmylee)
# Build a Rust tool if the binary doesn't exist or source has changed.
# Arguments:
#   $1 - tool name (directory name under tools/)
build_tool() {
    local tool_name="$1"
    local tool_dir="$TOOLS_DIR/$tool_name"
    local binary="$tool_dir/target/release/$tool_name"
    local src_dir="$tool_dir/src"
    local cargo_toml="$tool_dir/Cargo.toml"
    
    # Check if tool directory exists
    if [[ ! -d "$tool_dir" ]]; then
        log_error "Tool directory not found: $tool_dir"
        return 1
    fi
    
    # Check if Cargo.toml exists
    if [[ ! -f "$cargo_toml" ]]; then
        log_error "Cargo.toml not found: $cargo_toml"
        return 1
    fi
    
    # Determine if rebuild is needed
    local needs_build=false
    local reason=""
    
    if [[ ! -f "$binary" ]]; then
        needs_build=true
        reason="binary not found"
    elif [[ "$cargo_toml" -nt "$binary" ]]; then
        needs_build=true
        reason="Cargo.toml changed"
    elif [[ -n "$(find "$src_dir" -name '*.rs' -newer "$binary" 2>/dev/null | head -1)" ]]; then
        needs_build=true
        reason="source changed"
    fi
    
    if [[ "$needs_build" == "true" ]]; then
        log_step "Building $tool_name ($reason)..."
        
        # Build in release mode for optimal performance
        if ! (cd "$tool_dir" && cargo build --release --quiet 2>&1); then
            log_error "Failed to build $tool_name"
            return 1
        fi
        
        log_info "Built: $tool_name"
    fi
    
    return 0
}

# NOTE(jimmylee)
# Verify a tool binary exists and is executable.
verify_tool() {
    local tool_name="$1"
    local binary="$TOOLS_DIR/$tool_name/target/release/$tool_name"
    
    if [[ ! -x "$binary" ]]; then
        log_error "Tool binary not found or not executable: $binary"
        return 1
    fi
    
    return 0
}

# NOTE(jimmylee)
# Main function - builds all required Rust tools.
main() {
    # Check for Rust installation
    check_rust || exit 1
    
    # Build all Rust tools
    # Add new tools here as they are created
    build_tool "apply-edits" || exit 1
    
    # Verify all tools are ready
    verify_tool "apply-edits" || exit 1
    
    # Silent success - only log if something was built
}

main "$@"
