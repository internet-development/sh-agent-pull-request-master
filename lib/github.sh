#!/bin/bash
#
# NOTE(jimmylee)
# GitHub API utilities using curl. No gh CLI dependency.

[[ -n "${_GITHUB_SH_LOADED:-}" ]] && return 0
_GITHUB_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/json.sh"

# Legacy alias for backwards compatibility
github_json_escape() {
    json_escape "$1"
}

# NOTE(jimmylee)
# Makes a GitHub API request using curl
# Usage: github_api <method> <endpoint> [data]
github_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "ERROR: GITHUB_TOKEN not set" >&2
        return 1
    fi
    
    local url="https://api.github.com${endpoint}"
    local args=(
        -s
        -X "$method"
        -H "Authorization: Bearer ${GITHUB_TOKEN}"
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
    )
    
    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi
    
    curl "${args[@]}" "$url"
}

# NOTE(jimmylee)
# Get authenticated user info
# Returns the login username on success
github_get_user() {
    local response
    response=$(github_api GET "/user")
    
    if echo "$response" | grep -q '"login"'; then
        echo "$response" | grep -o '"login"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
        return 0
    else
        echo "ERROR: Failed to get user info" >&2
        return 1
    fi
}

# NOTE(jimmylee)
# Check if a repository is accessible
# Usage: github_check_repo <owner/repo>
github_check_repo() {
    local repo="$1"
    local response
    response=$(github_api GET "/repos/${repo}")
    
    if echo "$response" | grep -q '"full_name"'; then
        echo "$response" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
        return 0
    else
        echo "ERROR: Cannot access repository: $repo" >&2
        return 1
    fi
}

# NOTE(jimmylee)
# Get PR details
# Usage: github_get_pr <owner/repo> <pr_number>
github_get_pr() {
    local repo="$1"
    local pr_number="$2"
    
    github_api GET "/repos/${repo}/pulls/${pr_number}"
}

# NOTE(jimmylee)
# Get PR diff
# Usage: github_get_pr_diff <owner/repo> <pr_number>
github_get_pr_diff() {
    local repo="$1"
    local pr_number="$2"
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "ERROR: GITHUB_TOKEN not set" >&2
        return 1
    fi
    
    curl -s \
        "https://api.github.com/repos/${repo}/pulls/${pr_number}" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3.diff"
}

# NOTE(jimmylee)
# List open PRs for a branch
# Usage: github_list_prs <owner/repo> [head_branch]
github_list_prs() {
    local repo="$1"
    local head="${2:-}"
    
    local endpoint="/repos/${repo}/pulls?state=open"
    if [[ -n "$head" ]]; then
        endpoint="${endpoint}&head=${head}"
    fi
    
    github_api GET "$endpoint"
}

# NOTE(jimmylee)
# Test GitHub API connection
# Returns "PASS" on success, error message on failure
test_github_api() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "SKIP: GITHUB_TOKEN not set"
        return 1
    fi
    
    local user
    user=$(github_get_user 2>&1) || {
        echo "FAIL: $user"
        return 1
    }
    
    echo "PASS"
    return 0
}
