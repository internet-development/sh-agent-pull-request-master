#!/bin/bash
#
# NOTE(angeldev)
# Planning phase functions for the www-agent workflow.
# Handles repository cloning, codebase analysis, Director planning, research, and requirements synthesis.

[[ -n "${_PLANNING_SH_LOADED:-}" ]] && return 0
_PLANNING_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTERS_DIR="$(cd "$SCRIPT_DIR/../adapters" && pwd)"

# NOTE(jimmylee)
# Checks if Google Custom Search is configured for web research.
# Returns 0 (true) if configured, 1 (false) if not.
is_research_enabled() {
    if [[ -n "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" && -n "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        return 0
    else
        return 1
    fi
}

# NOTE(jimmylee)
# Clones the target repository to a working directory.
clone_target_repo() {
    local clean="${1:-false}"
    
    log "CLONE" "Cloning target repository: ${GITHUB_REPO_AGENTS_WILL_WORK_ON}"
    
    local clone_args=""
    if [[ "$clean" == "true" ]]; then
        clone_args="--clean"
    fi
    
    local clone_output
    clone_output=$("${ADAPTERS_DIR}/git-clone-repo.sh" $clone_args 2>&1) || {
        log_error "CLONE" "Failed to clone repository"
        echo "$clone_output" >&2
        return 1
    }
    
    TARGET_REPO_PATH=$(echo "$clone_output" | grep "CLONE_PATH:" | cut -d' ' -f2)
    
    if [[ -z "$TARGET_REPO_PATH" || ! -d "$TARGET_REPO_PATH" ]]; then
        log_error "CLONE" "Failed to determine clone path"
        return 1
    fi
    
    log_success "CLONE" "Repository ready at: $TARGET_REPO_PATH"
    export TARGET_REPO_PATH
}

# NOTE(jimmylee)
# Gets a comprehensive deep scan of the target repository.
# This gives the Director full understanding of the codebase before making decisions.
get_repo_context() {
    if [[ -z "$TARGET_REPO_PATH" ]]; then
        echo "ERROR: Target repo not cloned" >&2
        return 1
    fi
    
    local context=""
    
    # =========================================================================
    # SECTION 1: Complete file tree (no artificial limits)
    # =========================================================================
    context+="## Complete Repository Structure\n\n"
    context+="\`\`\`\n"
    context+=$(cd "$TARGET_REPO_PATH" && find . -type f \
        -not -path '*/\.*' \
        -not -path '*/node_modules/*' \
        -not -path '*/vendor/*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        -not -path '*/.next/*' \
        -not -path '*/coverage/*' \
        -not -name '*.lock' \
        -not -name 'package-lock.json' \
        -not -name 'yarn.lock' \
        -not -name 'pnpm-lock.yaml' \
        2>/dev/null | sort)
    context+="\n\`\`\`\n\n"
    
    # =========================================================================
    # SECTION 2: Full README (complete, not truncated)
    # =========================================================================
    if [[ -f "$TARGET_REPO_PATH/README.md" ]]; then
        context+="## README.md (Complete)\n\n"
        context+="\`\`\`markdown\n"
        context+=$(cat "$TARGET_REPO_PATH/README.md")
        context+="\n\`\`\`\n\n"
    fi
    
    # =========================================================================
    # SECTION 3: Configuration files (full contents)
    # =========================================================================
    context+="## Configuration Files\n\n"
    
    # Package.json
    if [[ -f "$TARGET_REPO_PATH/package.json" ]]; then
        context+="### package.json\n\n"
        context+="\`\`\`json\n"
        context+=$(cat "$TARGET_REPO_PATH/package.json")
        context+="\n\`\`\`\n\n"
    fi
    
    # TypeScript config
    if [[ -f "$TARGET_REPO_PATH/tsconfig.json" ]]; then
        context+="### tsconfig.json\n\n"
        context+="\`\`\`json\n"
        context+=$(cat "$TARGET_REPO_PATH/tsconfig.json")
        context+="\n\`\`\`\n\n"
    fi
    
    # Next.js config
    if [[ -f "$TARGET_REPO_PATH/next.config.js" ]]; then
        context+="### next.config.js\n\n"
        context+="\`\`\`javascript\n"
        context+=$(cat "$TARGET_REPO_PATH/next.config.js")
        context+="\n\`\`\`\n\n"
    elif [[ -f "$TARGET_REPO_PATH/next.config.mjs" ]]; then
        context+="### next.config.mjs\n\n"
        context+="\`\`\`javascript\n"
        context+=$(cat "$TARGET_REPO_PATH/next.config.mjs")
        context+="\n\`\`\`\n\n"
    elif [[ -f "$TARGET_REPO_PATH/next.config.ts" ]]; then
        context+="### next.config.ts\n\n"
        context+="\`\`\`typescript\n"
        context+=$(cat "$TARGET_REPO_PATH/next.config.ts")
        context+="\n\`\`\`\n\n"
    fi
    
    # Vite config
    if [[ -f "$TARGET_REPO_PATH/vite.config.ts" ]]; then
        context+="### vite.config.ts\n\n"
        context+="\`\`\`typescript\n"
        context+=$(cat "$TARGET_REPO_PATH/vite.config.ts")
        context+="\n\`\`\`\n\n"
    elif [[ -f "$TARGET_REPO_PATH/vite.config.js" ]]; then
        context+="### vite.config.js\n\n"
        context+="\`\`\`javascript\n"
        context+=$(cat "$TARGET_REPO_PATH/vite.config.js")
        context+="\n\`\`\`\n\n"
    fi
    
    # Tailwind config
    if [[ -f "$TARGET_REPO_PATH/tailwind.config.js" ]]; then
        context+="### tailwind.config.js\n\n"
        context+="\`\`\`javascript\n"
        context+=$(cat "$TARGET_REPO_PATH/tailwind.config.js")
        context+="\n\`\`\`\n\n"
    elif [[ -f "$TARGET_REPO_PATH/tailwind.config.ts" ]]; then
        context+="### tailwind.config.ts\n\n"
        context+="\`\`\`typescript\n"
        context+=$(cat "$TARGET_REPO_PATH/tailwind.config.ts")
        context+="\n\`\`\`\n\n"
    fi
    
    # ESLint config
    for eslint_file in ".eslintrc.js" ".eslintrc.json" ".eslintrc.cjs" "eslint.config.js" "eslint.config.mjs"; do
        if [[ -f "$TARGET_REPO_PATH/$eslint_file" ]]; then
            context+="### $eslint_file\n\n"
            context+="\`\`\`\n"
            context+=$(cat "$TARGET_REPO_PATH/$eslint_file")
            context+="\n\`\`\`\n\n"
            break
        fi
    done
    
    # Python configs
    if [[ -f "$TARGET_REPO_PATH/pyproject.toml" ]]; then
        context+="### pyproject.toml\n\n"
        context+="\`\`\`toml\n"
        context+=$(cat "$TARGET_REPO_PATH/pyproject.toml")
        context+="\n\`\`\`\n\n"
    fi
    
    if [[ -f "$TARGET_REPO_PATH/requirements.txt" ]]; then
        context+="### requirements.txt\n\n"
        context+="\`\`\`\n"
        context+=$(cat "$TARGET_REPO_PATH/requirements.txt")
        context+="\n\`\`\`\n\n"
    fi
    
    # Go config
    if [[ -f "$TARGET_REPO_PATH/go.mod" ]]; then
        context+="### go.mod\n\n"
        context+="\`\`\`\n"
        context+=$(cat "$TARGET_REPO_PATH/go.mod")
        context+="\n\`\`\`\n\n"
    fi
    
    # Rust config
    if [[ -f "$TARGET_REPO_PATH/Cargo.toml" ]]; then
        context+="### Cargo.toml\n\n"
        context+="\`\`\`toml\n"
        context+=$(cat "$TARGET_REPO_PATH/Cargo.toml")
        context+="\n\`\`\`\n\n"
    fi
    
    # Docker
    if [[ -f "$TARGET_REPO_PATH/Dockerfile" ]]; then
        context+="### Dockerfile\n\n"
        context+="\`\`\`dockerfile\n"
        context+=$(cat "$TARGET_REPO_PATH/Dockerfile")
        context+="\n\`\`\`\n\n"
    fi
    
    if [[ -f "$TARGET_REPO_PATH/docker-compose.yml" ]]; then
        context+="### docker-compose.yml\n\n"
        context+="\`\`\`yaml\n"
        context+=$(cat "$TARGET_REPO_PATH/docker-compose.yml")
        context+="\n\`\`\`\n\n"
    elif [[ -f "$TARGET_REPO_PATH/docker-compose.yaml" ]]; then
        context+="### docker-compose.yaml\n\n"
        context+="\`\`\`yaml\n"
        context+=$(cat "$TARGET_REPO_PATH/docker-compose.yaml")
        context+="\n\`\`\`\n\n"
    fi
    
    echo -e "$context"
}

# NOTE(angeldev)
# Prioritizes files for context based on relevance to the directive.
# Uses scoring to rank files by importance for the given task.
#
# Scoring algorithm:
# - +10 if filename contains directive keywords
# - +5 if path contains directive keywords
# - +3 for recently modified files
# - +2 for files imported by high-scoring files
# - +1 for common entry points and configs
#
# Returns a newline-separated list of prioritized file paths.
prioritize_files_for_context() {
    local directive="$1"
    local all_files="$2"
    local max_chars="${MAX_CODEBASE_CHARS:-640000}"

    # Extract keywords from directive (simple word extraction)
    local keywords
    keywords=$(echo "$directive" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | grep -E '^[a-z]{3,}$' | sort -u | head -20)

    if [[ -z "$keywords" ]]; then
        # No useful keywords, return original file list
        echo "$all_files"
        return
    fi

    # Create temp file for scoring
    local score_file
    score_file=$(make_temp_file "file_scores")

    # Score each file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local score=0
        local filename
        filename=$(basename "$file")
        local filepath_lower
        filepath_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
        local filename_lower
        filename_lower=$(echo "$filename" | tr '[:upper:]' '[:lower:]')

        # +10 for filename containing directive keywords
        for kw in $keywords; do
            if [[ "$filename_lower" == *"$kw"* ]]; then
                ((score += 10))
            fi
        done

        # +5 for path containing directive keywords
        for kw in $keywords; do
            if [[ "$filepath_lower" == *"$kw"* && "$filename_lower" != *"$kw"* ]]; then
                ((score += 5))
            fi
        done

        # +3 for common entry points
        case "$filename" in
            index.ts|index.tsx|index.js|index.jsx|main.ts|main.tsx|main.js|main.py|main.go|main.rs)
                ((score += 3))
                ;;
            app.ts|app.tsx|app.js|app.jsx|App.tsx|App.vue|App.svelte)
                ((score += 3))
                ;;
            routes.ts|router.ts|routes.js|router.js)
                ((score += 2))
                ;;
        esac

        # +2 for config files (always useful)
        case "$filename" in
            package.json|tsconfig.json|next.config.*|vite.config.*|tailwind.config.*)
                ((score += 2))
                ;;
        esac

        # +1 for core directories
        if [[ "$file" == *"/src/lib/"* || "$file" == *"/src/utils/"* || "$file" == *"/src/core/"* || "$file" == *"/src/api/"* ]]; then
            ((score += 1))
        fi

        echo "$score $file" >> "$score_file"
    done <<< "$all_files"

    # Sort by score descending and return files
    sort -t' ' -k1 -nr "$score_file" | awk '{print $2}'

    rm -f "$score_file"
}

# NOTE(angeldev)
# Gets recently modified files from git history (within last 30 commits).
# Returns newline-separated list of file paths.
get_recently_modified_files() {
    if [[ -z "$TARGET_REPO_PATH" ]]; then
        return
    fi

    cd "$TARGET_REPO_PATH" && git log --name-only --pretty=format: -30 2>/dev/null | \
        grep -v '^$' | sort -u | head -50
}

# NOTE(jimmylee)
# Performs deep source code analysis with smart token budget management.
# Prioritizes high-value files (entry points, configs, core modules) and
# provides summaries for less critical files to stay within context limits.
analyze_codebase_deep() {
    if [[ -z "$TARGET_REPO_PATH" ]]; then
        echo "ERROR: Target repo not cloned" >&2
        return 1
    fi
    
    local analysis=""
    local max_chars="${MAX_CODEBASE_CHARS:-640000}"
    local current_chars=0
    
    analysis+="## Deep Codebase Analysis\n\n"
    
    # =========================================================================
    # PRIORITY 1: Entry points and main files (always include full content)
    # =========================================================================
    local priority_patterns=(
        "index.ts" "index.tsx" "index.js" "index.jsx"
        "main.ts" "main.tsx" "main.js" "main.jsx" "main.py" "main.go" "main.rs"
        "app.ts" "app.tsx" "app.js" "app.jsx" "app.py"
        "server.ts" "server.js" "server.py" "server.go"
        "lib.rs" "mod.rs"
        "App.tsx" "App.jsx" "App.vue" "App.svelte"
        "_app.tsx" "_app.jsx" "_document.tsx" "_document.jsx"
        "layout.tsx" "layout.jsx" "page.tsx" "page.jsx"
        "routes.ts" "routes.js" "router.ts" "router.js"
        "schema.ts" "schema.js" "schema.graphql" "schema.prisma"
        "types.ts" "types.d.ts" "interfaces.ts"
        "constants.ts" "constants.js" "config.ts" "config.js"
        "utils.ts" "utils.js" "helpers.ts" "helpers.js"
        "api.ts" "api.js" "client.ts" "client.js"
        "database.ts" "database.js" "db.ts" "db.js"
        "auth.ts" "auth.js" "middleware.ts" "middleware.js"
    )
    
    analysis+="### Priority Files (Entry Points & Core)\n\n"
    
    local priority_files=""
    for pattern in "${priority_patterns[@]}"; do
        local found
        found=$(cd "$TARGET_REPO_PATH" && find . -type f -name "$pattern" \
            -not -path '*/node_modules/*' \
            -not -path '*/\.*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            2>/dev/null | head -5)
        if [[ -n "$found" ]]; then
            priority_files+="$found"$'\n'
        fi
    done
    
    # Also find files in src/lib, src/utils, src/core, src/api, app/, pages/
    local core_dirs=("src/lib" "src/utils" "src/core" "src/api" "src/services" "src/hooks" "lib" "app" "pages" "api" "components")
    for dir in "${core_dirs[@]}"; do
        if [[ -d "$TARGET_REPO_PATH/$dir" ]]; then
            local dir_files
            dir_files=$(cd "$TARGET_REPO_PATH" && find "./$dir" -maxdepth 2 -type f \( \
                -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o \
                -name "*.py" -o -name "*.go" -o -name "*.rs" \
                \) 2>/dev/null | head -20)
            priority_files+="$dir_files"$'\n'
        fi
    done
    
    # Deduplicate and sort
    priority_files=$(echo "$priority_files" | sort -u | grep -v '^$')
    
    local file_count=0
    local included_files=()
    local summarized_files=()
    
    # Read priority files
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        local full_path="$TARGET_REPO_PATH/${file#./}"
        [[ ! -f "$full_path" ]] && continue
        
        local file_content
        file_content=$(cat "$full_path" 2>/dev/null) || continue
        local content_size=${#file_content}
        
        # Check if adding this file would exceed budget
        if (( current_chars + content_size > max_chars )); then
            # Add to summarized list instead
            local line_count
            line_count=$(echo "$file_content" | wc -l | tr -d ' ')
            summarized_files+=("${file#./} ($line_count lines)")
            continue
        fi
        
        local extension="${file##*.}"
        local lang=""
        case "$extension" in
            ts|tsx) lang="typescript" ;;
            js|jsx|mjs|cjs) lang="javascript" ;;
            py) lang="python" ;;
            go) lang="go" ;;
            rs) lang="rust" ;;
            vue) lang="vue" ;;
            svelte) lang="svelte" ;;
            *) lang="$extension" ;;
        esac
        
        analysis+="#### ${file#./}\n\n"
        analysis+="\`\`\`${lang}\n"
        analysis+="$file_content"
        analysis+="\n\`\`\`\n\n"
        
        ((current_chars += content_size))
        ((file_count++))
        included_files+=("${file#./}")
        
    done <<< "$priority_files"
    
    # =========================================================================
    # PRIORITY 2: Remaining source files (include if budget allows)
    # =========================================================================
    local remaining_files
    remaining_files=$(cd "$TARGET_REPO_PATH" && find . -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o \
        -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.rb" -o \
        -name "*.vue" -o -name "*.svelte" \
        \) \
        -not -path '*/\.*' \
        -not -path '*/node_modules/*' \
        -not -path '*/vendor/*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        -not -path '*/.next/*' \
        -not -path '*/coverage/*' \
        -not -name '*.min.js' \
        -not -name '*.test.*' \
        -not -name '*.spec.*' \
        -not -name '*.stories.*' \
        2>/dev/null | sort)
    
    if (( current_chars < max_chars )); then
        analysis+="\n### Additional Source Files\n\n"
        
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            
            # Skip if already included
            local already_included=false
            for inc in "${included_files[@]}"; do
                if [[ "${file#./}" == "$inc" ]]; then
                    already_included=true
                    break
                fi
            done
            [[ "$already_included" == "true" ]] && continue
            
            local full_path="$TARGET_REPO_PATH/${file#./}"
            [[ ! -f "$full_path" ]] && continue
            
            local file_content
            file_content=$(cat "$full_path" 2>/dev/null) || continue
            local content_size=${#file_content}
            local line_count
            line_count=$(echo "$file_content" | wc -l | tr -d ' ')
            
            # Check budget
            if (( current_chars + content_size > max_chars )); then
                summarized_files+=("${file#./} ($line_count lines)")
                continue
            fi
            
            local extension="${file##*.}"
            local lang=""
            case "$extension" in
                ts|tsx) lang="typescript" ;;
                js|jsx|mjs|cjs) lang="javascript" ;;
                py) lang="python" ;;
                go) lang="go" ;;
                rs) lang="rust" ;;
                vue) lang="vue" ;;
                svelte) lang="svelte" ;;
                *) lang="$extension" ;;
            esac
            
            analysis+="#### ${file#./}\n\n"
            analysis+="\`\`\`${lang}\n"
            analysis+="$file_content"
            analysis+="\n\`\`\`\n\n"
            
            ((current_chars += content_size))
            ((file_count++))
            included_files+=("${file#./}")
            
        done <<< "$remaining_files"
    fi
    
    # =========================================================================
    # Add summary of files that couldn't be included
    # =========================================================================
    if [[ ${#summarized_files[@]} -gt 0 ]]; then
        analysis+="\n### Files Not Fully Included (token budget)\n\n"
        analysis+="The following files exist but were summarized to stay within context limits:\n\n"
        for sf in "${summarized_files[@]}"; do
            analysis+="- $sf\n"
        done
        analysis+="\nIf you need to see any of these files, they can be read during implementation.\n\n"
    fi
    
    # =========================================================================
    # Add statistics
    # =========================================================================
    local summary="## Codebase Analysis Statistics\n\n"
    summary+="- **Files fully analyzed**: $file_count\n"
    summary+="- **Files summarized**: ${#summarized_files[@]}\n"
    summary+="- **Approximate tokens used**: $((current_chars / 4))\n\n"
    
    echo -e "${summary}${analysis}"
}

# NOTE(jimmylee)
# Director creates initial execution plan with FULL codebase understanding.
create_director_plan() {
    local directive="$1"
    local full_context="$2"
    
    local personas_list
    personas_list=$(list_personas | tr '\n' ', ' | sed 's/,$//')
    
    # Get current date for context
    local current_date
    current_date=$(date "+%B %d, %Y")
    
    local prompt="## Today's Date: ${current_date}

Use this date to assess whether information, package versions, and documentation are current.

## Directive

${directive}

## Target Repository: ${GITHUB_REPO_AGENTS_WILL_WORK_ON}

## IMPORTANT: Full Codebase Analysis

You have been given the COMPLETE source code of the entire repository below.
This includes every source file, configuration file, and documentation.
Use this deep understanding to make informed decisions about:
- How the codebase is structured and organized
- What patterns, conventions, and styles are used
- What dependencies and technologies are in use
- Where changes would need to be made
- What could break if changes are made incorrectly

${full_context}

## Available Personas

${personas_list}

## Task

With FULL visibility into the codebase, analyze this directive and create an execution plan.

1. Based on deep understanding of the code, what specifically needs to be done?
2. Which files will likely need to be modified or created?
3. Are there any external dependencies, packages, or APIs that need current information verified via web research?
4. Which perspectives should be consulted before implementation starts?
5. What are the key acceptance criteria based on the existing code patterns?
6. What risks are foreseeable given the current codebase structure?

Output a JSON plan:

\`\`\`json
{
  \"understanding\": \"Interpretation of the directive based on full codebase analysis\",
  \"codebase_insights\": \"Key observations about the codebase structure, patterns, and conventions\",
  \"research_queries\": [\"Questions requiring web research to verify current facts - e.g. 'What is the latest stable version of Next.js?' or 'React 19 Server Components API' - leave as empty array [] if no research needed\"],
  \"files_to_modify\": [\"path/to/file1.ts\", \"path/to/file2.ts\"],
  \"files_to_create\": [\"path/to/new-file.ts\"],
  \"consult_personas\": [\"project-manager\", \"researcher\", \"technical-writer\"],
  \"acceptance_criteria\": [\"criterion 1\", \"criterion 2\"],
  \"risks\": [\"risk 1\"],
  \"questions_for_personas\": {
    \"project-manager\": \"What scope and priority considerations should we have?\",
    \"researcher\": \"Are there any best practices or patterns we should follow?\",
    \"technical-writer\": \"What documentation standards should we maintain?\"
  }
}
\`\`\`"

    invoke_persona "director" "$prompt"
}

# NOTE(jimmylee)
# Conducts web research using Google Custom Search API.
conduct_web_research() {
    local research_queries_json="$1"
    local directive="$2"
    
    # Check if there are any queries
    local query_count
    query_count=$(echo "$research_queries_json" | jq 'length' 2>/dev/null) || query_count=0
    
    if [[ "$query_count" -eq 0 || "$research_queries_json" == "null" || "$research_queries_json" == "[]" ]]; then
        log "RESEARCH" "No research queries requested by Director"
        echo '{"research_conducted": false, "findings": [], "summary": "No research was needed for this task."}'
        return 0
    fi
    
    # Check if Google Search is configured
    if [[ -z "${API_KEY_GOOGLE_CUSTOM_SEARCH:-}" ]]; then
        log_warning "RESEARCH" "API_KEY_GOOGLE_CUSTOM_SEARCH not set - skipping web research"
        echo '{"research_conducted": false, "findings": [], "summary": "Web research unavailable. Proceeding with existing knowledge."}'
        return 0
    fi
    
    if [[ -z "${GOOGLE_CUSTOM_SEARCH_ID:-}" ]]; then
        log_warning "RESEARCH" "GOOGLE_CUSTOM_SEARCH_ID not set - skipping web research"
        echo '{"research_conducted": false, "findings": [], "summary": "Web research unavailable. Proceeding with existing knowledge."}'
        return 0
    fi
    
    log "RESEARCH" "Conducting web research on $query_count topic(s)..."
    
    local all_search_results="[]"
    local queries_searched="[]"
    
    # Helper function to extract and format Google search results
    extract_search_results() {
        local raw_results="$1"
        local query="$2"
        local search_type="$3"
        
        echo "$raw_results" | jq --arg query "$query" --arg search_type "$search_type" '{
            query: $query,
            search_type: $search_type,
            results: [.items[]? | {
                url: .link,
                title: .title,
                snippet: .snippet,
                displayLink: .displayLink,
                formattedUrl: .formattedUrl,
                metatags: ((.pagemap.metatags[0] // {}) | {
                    description: (.["og:description"] // .description // null),
                    site_name: (.["og:site_name"] // null),
                    type: (.["og:type"] // null),
                    published_time: (.["article:published_time"] // null),
                    modified_time: (.["article:modified_time"] // null)
                }),
                article: (.pagemap.article[0] // null),
                softwareapp: (.pagemap.softwareapplication[0] // null)
            }]
        }' 2>/dev/null
    }
    
    # Process each query with smart search strategy
    local i=0
    while [[ $i -lt $query_count ]]; do
        local query
        query=$(echo "$research_queries_json" | jq -r ".[$i]")
        
        log "RESEARCH" "Searching: $query"
        
        local combined_results="[]"
        local total_found=0
        
        # Strategy 1: Search recent results first (past year)
        log "RESEARCH" "  -> Searching recent results (past year)..."
        local recent_results
        if recent_results=$(call_google_search "$query" 5 "y1" "" 2>/dev/null); then
            local recent_json
            recent_json=$(extract_search_results "$recent_results" "$query" "recent")
            if [[ -n "$recent_json" && "$recent_json" != "null" ]]; then
                local recent_count
                recent_count=$(echo "$recent_json" | jq '.results | length')
                if [[ "$recent_count" -gt 0 ]]; then
                    combined_results=$(echo "$combined_results" | jq ". + $(echo "$recent_json" | jq '.results')")
                    total_found=$((total_found + recent_count))
                    log "RESEARCH" "  -> Found $recent_count recent results"
                fi
            fi
        fi
        
        request_spacing 300
        
        # Strategy 2: Search by relevance (no date restriction)
        log "RESEARCH" "  -> Searching by relevance..."
        local relevance_results
        if relevance_results=$(call_google_search "$query" 5 "" "" 2>/dev/null); then
            local relevance_json
            relevance_json=$(extract_search_results "$relevance_results" "$query" "relevance")
            if [[ -n "$relevance_json" && "$relevance_json" != "null" ]]; then
                local relevance_count
                relevance_count=$(echo "$relevance_json" | jq '.results | length')
                if [[ "$relevance_count" -gt 0 ]]; then
                    # Add results that aren't already in combined (dedupe by URL)
                    local new_results
                    new_results=$(echo "$relevance_json" | jq --argjson existing "$combined_results" '
                        .results | map(select(.url as $url | $existing | map(.url) | index($url) | not))
                    ')
                    local new_count
                    new_count=$(echo "$new_results" | jq 'length')
                    if [[ "$new_count" -gt 0 ]]; then
                        combined_results=$(echo "$combined_results" | jq ". + $new_results")
                        total_found=$((total_found + new_count))
                        log "RESEARCH" "  -> Found $new_count additional results by relevance"
                    fi
                fi
            fi
        fi
        
        # Format the combined results
        if [[ "$total_found" -gt 0 ]]; then
            local results_json
            results_json=$(echo "{}" | jq --arg query "$query" --argjson results "$combined_results" '{
                query: $query,
                results: $results
            }')
            
            all_search_results=$(echo "$all_search_results" | jq ". + [$results_json]")
            queries_searched=$(echo "$queries_searched" | jq ". + [\"$query\"]")
            
            log_success "RESEARCH" "Found $total_found total results for: $query"
        else
            log_warning "RESEARCH" "No results found for: $query"
        fi
        
        ((i++))
        request_spacing 500
    done
    
    # Check if we got any results
    local total_results
    total_results=$(echo "$all_search_results" | jq 'length')
    
    if [[ "$total_results" -eq 0 ]]; then
        log_warning "RESEARCH" "No search results obtained"
        echo '{"research_conducted": false, "findings": [], "summary": "Web search returned no results. Proceeding with existing knowledge."}'
        return 0
    fi
    
    # Have Researcher persona synthesize the findings
    log "RESEARCH" "Synthesizing research findings..."
    
    local formatted_results
    formatted_results=$(echo "$all_search_results" | jq -r '
        .[] | "### Query: \(.query)\n" + (
            .results[] | 
            "- **\(.title)**\n" +
            "  Source: \(.displayLink // .formattedUrl // .url)\n" +
            "  URL: \(.url)\n" +
            (if .metatags.published_time then "  Published: \(.metatags.published_time)\n" else "" end) +
            (if .metatags.modified_time then "  Modified: \(.metatags.modified_time)\n" else "" end) +
            (if .metatags.site_name then "  Site: \(.metatags.site_name)\n" else "" end) +
            (if .softwareapp.name then "  Package: \(.softwareapp.name) v\(.softwareapp.version // "?")\n" else "" end) +
            (if .metatags.description and .metatags.description != .snippet then "  Description: \(.metatags.description)\n" else "" end) +
            "  Snippet: \(.snippet // "(no snippet)")\n"
        )
    ' 2>/dev/null)
    
    local current_date
    current_date=$(date "+%B %d, %Y")
    
    local synthesis_prompt="## Web Search Results Analysis

**Today's Date:** ${current_date}

Use this date to assess whether search results are current or outdated.

The following web search results were gathered to inform this task:

**Directive:** ${directive}

**Search Results:**

${formatted_results}

## Task

Analyze these search results and extract actionable information:

1. For each query, what is the definitive answer based on the sources?
2. What specific facts (versions, APIs, dates) were found?
3. Are there any warnings, deprecations, or security concerns mentioned?
4. What should the implementation specifically do based on these findings?

Be precise and cite specific information from the sources. If sources conflict, note the conflict.

Output your analysis as JSON:

\`\`\`json
{
  \"findings\": [
    {
      \"query\": \"the original search query\",
      \"answer\": \"clear, direct answer based on sources\",
      \"confidence\": \"high|medium|low\",
      \"key_facts\": [\"specific fact 1\", \"specific fact 2\"],
      \"sources\": [{\"url\": \"source url\", \"title\": \"source title\"}]
    }
  ],
  \"summary\": \"Brief overall synthesis of what was learned and how it applies to the task\",
  \"warnings\": [\"any critical warnings, deprecations, or security concerns found\"]
}
\`\`\`"

    local synthesis
    if synthesis=$(invoke_persona "researcher" "$synthesis_prompt" 2>/dev/null); then
        local findings_json
        if echo "$synthesis" | grep -q '```json'; then
            findings_json=$(echo "$synthesis" | sed -n '/```json/,/```/p' | sed '1d;$d')
        else
            findings_json="$synthesis"
        fi
        
        if echo "$findings_json" | jq empty 2>/dev/null; then
            local final_output
            final_output=$(echo "$findings_json" | jq --argjson queries "$queries_searched" '. + {research_conducted: true, queries_searched: $queries}')
            
            log_success "RESEARCH" "Research synthesis complete"
            
            log_subsection "RESEARCH FINDINGS SUMMARY"
            echo "$final_output" | jq -r '.summary // "No summary"' | while IFS= read -r line; do
                log "RESEARCH" "$line"
            done
            echo "$final_output" | jq -r '.findings[]? | "  - \(.query): \(.answer) [\(.confidence)]"' | while IFS= read -r line; do
                log "RESEARCH" "$line"
            done
            
            echo "$final_output"
            return 0
        else
            log_warning "RESEARCH" "Could not parse synthesis JSON"
        fi
    else
        log_warning "RESEARCH" "Failed to synthesize findings"
    fi
    
    echo '{"research_conducted": true, "findings": [], "summary": "Research was conducted but synthesis failed. Raw results were collected.", "queries_searched": '"$queries_searched"'}'
}

# NOTE(jimmylee)
# Get input from a specific persona on the plan
get_persona_input() {
    local persona_name="$1"
    local directive="$2"
    local question="$3"
    local repo_context="$4"
    local research_findings="${5:-}"
    
    # Build research section if findings are available
    local research_section=""
    if [[ -n "$research_findings" && "$research_findings" != "null" ]]; then
        local has_findings
        has_findings=$(echo "$research_findings" | jq -r '.research_conducted // false' 2>/dev/null)
        if [[ "$has_findings" == "true" ]]; then
            local summary
            summary=$(echo "$research_findings" | jq -r '.summary // "No summary available"' 2>/dev/null)
            local findings_text
            findings_text=$(echo "$research_findings" | jq -r '.findings[]? | "### \(.query)\n**Answer:** \(.answer)\n**Confidence:** \(.confidence)\n**Key Facts:** \(.key_facts | join(", "))\n"' 2>/dev/null)
            local warnings_text
            warnings_text=$(echo "$research_findings" | jq -r 'if .warnings and (.warnings | length > 0) then "**Warnings:**\n" + (.warnings | map("- " + .) | join("\n")) else "" end' 2>/dev/null)
            
            research_section="## Verified Facts from Web Research

${summary}

${findings_text}
${warnings_text}

Use these verified facts to inform recommendations.

"
        fi
    fi
    
    local prompt="## Directive Being Worked On

${directive}

## Target Repository

${GITHUB_REPO_AGENTS_WILL_WORK_ON}

${repo_context}

${research_section}## Question to Consider

${question}

## Task

Provide perspective and recommendations based on this area of expertise. Be specific and actionable.
What should be known before implementing this? What constraints or guidelines should be followed?"

    invoke_persona "$persona_name" "$prompt"
}

# NOTE(jimmylee)
# Director synthesizes all persona input into final requirements for Engineer.
synthesize_requirements() {
    local directive="$1"
    local all_input="$2"
    local repo_context="$3"
    local research_findings="${4:-}"
    
    # Build research section if findings are available
    local research_section=""
    if [[ -n "$research_findings" && "$research_findings" != "null" ]]; then
        local has_findings
        has_findings=$(echo "$research_findings" | jq -r '.research_conducted // false' 2>/dev/null)
        if [[ "$has_findings" == "true" ]]; then
            local summary
            summary=$(echo "$research_findings" | jq -r '.summary // "No summary available"' 2>/dev/null)
            local findings_text
            findings_text=$(echo "$research_findings" | jq -r '.findings[]? | "- **\(.query)**: \(.answer) (confidence: \(.confidence))"' 2>/dev/null)
            local warnings_text
            warnings_text=$(echo "$research_findings" | jq -r 'if .warnings and (.warnings | length > 0) then "\n**WARNINGS from research:**\n" + (.warnings | map("- " + .) | join("\n")) else "" end' 2>/dev/null)
            
            research_section="## Verified Facts from Web Research

${summary}

${findings_text}
${warnings_text}

IMPORTANT: These verified facts MUST be reflected in the requirements. If research found specific versions, APIs, or warnings, incorporate them as constraints.

"
        fi
    fi
    
    local prompt="## Original Directive

${directive}

## Input from All Personas

${all_input}

${research_section}## Target Repository

${GITHUB_REPO_AGENTS_WILL_WORK_ON}

${repo_context}

## Task

Synthesize all the input from the different perspectives into a clear, actionable set of requirements for implementation.

CRITICAL: Define VERY CLEAR scope boundaries. The implementation must know:
1. EXACTLY which files to modify (be specific with paths)
2. EXACTLY what changes to make in each file
3. EXACTLY what is OUT OF SCOPE and must NOT be touched

For EACH suggestion from each persona, you must evaluate it and decide:
- \"incorporate\" = We will incorporate this suggestion (👍)
- \"already_done\" = This is already addressed or was part of our plan (✅)
- \"skip\" = We're skipping this suggestion as out of scope or not applicable (👎)

Output a JSON specification:

\`\`\`json
{
  \"task_summary\": \"Clear description of what needs to be built\",
  \"requirements\": [
    \"Specific requirement 1\",
    \"Specific requirement 2\"
  ],
  \"constraints\": [
    \"Constraint from project-manager\",
    \"Constraint from technical-writer\"
  ],
  \"acceptance_criteria\": [
    \"Testable criterion 1\",
    \"Testable criterion 2\"
  ],
  \"files_to_create\": [\"path/to/new-file.ts\"],
  \"files_to_modify\": [\"path/to/existing-file.ts\"],
  \"files_likely_affected\": [\"path/to/file1.js\", \"path/to/file2.js\"],
  \"out_of_scope\": [
    \"Do NOT modify any files not listed above\",
    \"Do NOT refactor existing code\",
    \"Do NOT add features beyond what is specified\",
    \"Do NOT change formatting or style of existing code\",
    \"Specific thing that should not be done\"
  ],
  \"suggestion_decisions\": [
    {
      \"persona\": \"project-manager\",
      \"suggestion\": \"Brief description of their suggestion\",
      \"decision\": \"incorporate|already_done|skip\",
      \"reason\": \"Brief reason for decision\"
    }
  ]
}
\`\`\`

Be VERY explicit about what is out of scope. The Engineer should have no ambiguity about what NOT to do."

    invoke_persona "director" "$prompt"
}

# NOTE(jimmylee)
# Formats suggestion decisions as a GitHub-friendly table for PR comments.
format_decisions_table() {
    local requirements_json="$1"
    
    local suggestion_count
    suggestion_count=$(echo "$requirements_json" | jq -r '.suggestion_decisions | length // 0' 2>/dev/null) || suggestion_count=0
    
    if [[ "$suggestion_count" -eq 0 ]]; then
        echo ""
        return
    fi
    
    # Build markdown table with Decision and Reason columns
    local table="| Decision | Reason |\n"
    table+="| --- | --- |\n"
    
    for i in $(seq 0 $((suggestion_count - 1))); do
        local suggestion decision reason emoji decision_text
        suggestion=$(echo "$requirements_json" | jq -r ".suggestion_decisions[$i].suggestion // \"\"")
        decision=$(echo "$requirements_json" | jq -r ".suggestion_decisions[$i].decision // \"skip\"")
        reason=$(echo "$requirements_json" | jq -r ".suggestion_decisions[$i].reason // \"\"")
        
        case "$decision" in
            incorporate)
                emoji="✅"
                decision_text="$suggestion"
                ;;
            already_done)
                emoji="✅"
                decision_text="$suggestion"
                reason="Already addressed - $reason"
                ;;
            skip)
                emoji="⏭️"
                decision_text="$suggestion"
                reason="Skipping (side effect) - $reason"
                ;;
            *)
                emoji="❓"
                decision_text="$suggestion"
                ;;
        esac
        
        # Add table row - escape pipe characters in content
        local escaped_decision="${emoji} ${decision_text//|/\\|}"
        local escaped_reason="${reason//|/\\|}"
        table+="| ${escaped_decision} | ${escaped_reason} |\n"
    done
    
    echo -e "$table"
}
