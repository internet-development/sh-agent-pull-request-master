#!/usr/bin/env bash
# NOTE(jimmylee): GitHub API utilities with token validation

# Validates GitHub token and checks required permissions
# Fails fast with clear error messages if validation fails
validate_github_token_access() {
    local token="$1"
    local repo="$2"
    
    if [[ -z "$token" ]]; then
        echo "ERROR: GITHUB_TOKEN is not set or empty" >&2
        return 1
    fi
    
    # Create temp files for response handling
    local headers_file
    local body_file
    headers_file=$(mktemp)
    body_file=$(mktemp)
    
    # Cleanup on exit
    trap "rm -f '$headers_file' '$body_file'" RETURN
    
    # Make API call capturing headers and body separately
    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -D "$headers_file" \
        -o "$body_file" \
        "https://api.github.com/user")
    
    # Check HTTP status
    if [[ "$http_code" != "200" ]]; then
        echo "ERROR: GitHub token authentication failed (HTTP $http_code)" >&2
        if [[ -f "$body_file" ]]; then
            local message
            message=$(jq -r '.message // empty' "$body_file" 2>/dev/null)
            [[ -n "$message" ]] && echo "  GitHub says: $message" >&2
        fi
        return 1
    fi
    
    # Extract OAuth scopes from headers (only present for classic tokens)
    local oauth_scopes
    oauth_scopes=$(grep -i '^x-oauth-scopes:' "$headers_file" | cut -d':' -f2- | tr -d '[:space:]')
    
    # Check if this is a classic token (has X-OAuth-Scopes header)
    if [[ -n "$oauth_scopes" ]]; then
        # Classic token - validate required scopes
        local has_repo_scope=false
        local has_discussion_scope=false
        
        # Check for repo or public_repo scope
        if echo "$oauth_scopes" | grep -qE '(^|,)repo(,|$)'; then
            has_repo_scope=true
        elif echo "$oauth_scopes" | grep -qE '(^|,)public_repo(,|$)'; then
            has_repo_scope=true
        fi
        
        # Check for write:discussion scope
        if echo "$oauth_scopes" | grep -qE '(^|,)write:discussion(,|$)'; then
            has_discussion_scope=true
        fi
        
        if [[ "$has_repo_scope" != "true" ]]; then
            echo "ERROR: GitHub classic token missing required scope" >&2
            echo "  Required: 'repo' or 'public_repo'" >&2
            echo "  Found scopes: $oauth_scopes" >&2
            echo "  Please create a new token with the required scopes" >&2
            return 1
        fi
        
        if [[ "$has_discussion_scope" != "true" ]]; then
            echo "WARNING: GitHub classic token missing 'write:discussion' scope" >&2
            echo "  PR comments may fail without this scope" >&2
            # Don't fail, just warn - PR creation can still work
        fi
        
        echo "✓ Classic token validated with scopes: $oauth_scopes" >&2
    else
        # Fine-grained token or GitHub App token - no scope header
        # Permissions are enforced at operation time by GitHub
        echo "✓ Token authenticated (fine-grained or app token - permissions checked at operation time)" >&2
    fi
    
    # If repo is specified, validate repository access
    if [[ -n "$repo" ]]; then
        local repo_http_code
        repo_http_code=$(curl -s -w "%{http_code}" \
            -H "Authorization: Bearer $token" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -o "$body_file" \
            "https://api.github.com/repos/$repo")
        
        if [[ "$repo_http_code" != "200" ]]; then
            echo "ERROR: Cannot access repository '$repo' (HTTP $repo_http_code)" >&2
            if [[ -f "$body_file" ]]; then
                local message
                message=$(jq -r '.message // empty' "$body_file" 2>/dev/null)
                [[ -n "$message" ]] && echo "  GitHub says: $message" >&2
            fi
            return 1
        fi
        
        echo "✓ Repository access verified: $repo" >&2
    fi
    
    return 0
}

# Makes a GitHub API request with proper error handling
# Usage: github_api_request <method> <endpoint> [data]
github_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local token="${GITHUB_TOKEN:-}"
    
    if [[ -z "$token" ]]; then
        echo "ERROR: GITHUB_TOKEN not set" >&2
        return 1
    fi
    
    local body_file
    body_file=$(mktemp)
    trap "rm -f '$body_file'" RETURN
    
    local curl_args=(
        -s
        -w "%{http_code}"
        -X "$method"
        -H "Authorization: Bearer $token"
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
        -o "$body_file"
    )
    
    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi
    
    local http_code
    http_code=$(curl "${curl_args[@]}" "https://api.github.com$endpoint")
    
    # Output the body
    cat "$body_file"
    
    # Return success/failure based on HTTP code
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        return 0
    else
        return 1
    fi
}
