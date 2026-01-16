#!/bin/bash
# Adapter: Detect validation commands available in a repository
#
# Usage: ./detect-validation.sh --workdir <path>
#
# This script detects what validation commands (test, build, lint) are available
# in a repository by examining common configuration files.
#
# Output: Key-value pairs for detected commands
#   VALIDATION_TEST=<command or empty>
#   VALIDATION_BUILD=<command or empty>
#   VALIDATION_LINT=<command or empty>
#   VALIDATION_TYPECHECK=<command or empty>
#
# If no validation is detected, all values will be empty.

set -euo pipefail

WORKDIR="."

# NOTE(jimmylee)
# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

cd "$WORKDIR"

VALIDATION_TEST=""
VALIDATION_BUILD=""
VALIDATION_LINT=""
VALIDATION_TYPECHECK=""

# NOTE(jimmylee)
# Helper: check if a command exists in package.json scripts
check_npm_script() {
    local script="$1"
    if [[ -f "package.json" ]]; then
        if jq -e ".scripts.\"$script\"" package.json > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# NOTE(jimmylee)
# Helper: check if Makefile has a target
check_make_target() {
    local target="$1"
    if [[ -f "Makefile" ]]; then
        if grep -qE "^${target}:" Makefile 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# NOTE(jimmylee)
# Node.js / JavaScript / TypeScript projects
if [[ -f "package.json" ]]; then
    echo "# Detected: Node.js project (package.json)" >&2

    # Determine package manager
    PKG_MANAGER="npm"
    if [[ -f "pnpm-lock.yaml" ]]; then
        PKG_MANAGER="pnpm"
    elif [[ -f "yarn.lock" ]]; then
        PKG_MANAGER="yarn"
    elif [[ -f "bun.lockb" ]]; then
        PKG_MANAGER="bun"
    fi

    # Test command
    if check_npm_script "test"; then
        VALIDATION_TEST="$PKG_MANAGER test"
    elif check_npm_script "test:unit"; then
        VALIDATION_TEST="$PKG_MANAGER run test:unit"
    fi

    # Build command
    if check_npm_script "build"; then
        VALIDATION_BUILD="$PKG_MANAGER run build"
    fi

    # Lint command
    if check_npm_script "lint"; then
        VALIDATION_LINT="$PKG_MANAGER run lint"
    elif check_npm_script "eslint"; then
        VALIDATION_LINT="$PKG_MANAGER run eslint"
    fi

    # Typecheck command
    if check_npm_script "typecheck"; then
        VALIDATION_TYPECHECK="$PKG_MANAGER run typecheck"
    elif check_npm_script "type-check"; then
        VALIDATION_TYPECHECK="$PKG_MANAGER run type-check"
    elif check_npm_script "tsc"; then
        VALIDATION_TYPECHECK="$PKG_MANAGER run tsc"
    elif [[ -f "tsconfig.json" ]]; then
        # TypeScript project without explicit typecheck script
        VALIDATION_TYPECHECK="npx tsc --noEmit"
    fi
fi

# NOTE(jimmylee)
# Python projects
if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
    echo "# Detected: Python project" >&2

    # Test command
    if [[ -d "tests" ]] || [[ -d "test" ]]; then
        if [[ -f "pyproject.toml" ]] && grep -q "pytest" pyproject.toml 2>/dev/null; then
            VALIDATION_TEST="${VALIDATION_TEST:-pytest}"
        elif [[ -f "requirements.txt" ]] && grep -q "pytest" requirements.txt 2>/dev/null; then
            VALIDATION_TEST="${VALIDATION_TEST:-pytest}"
        elif [[ -f "setup.py" ]]; then
            VALIDATION_TEST="${VALIDATION_TEST:-python -m pytest}"
        fi
    fi

    # Lint command
    if [[ -f "pyproject.toml" ]] && grep -q "ruff" pyproject.toml 2>/dev/null; then
        VALIDATION_LINT="${VALIDATION_LINT:-ruff check .}"
    elif [[ -f ".flake8" ]] || grep -q "flake8" requirements.txt 2>/dev/null; then
        VALIDATION_LINT="${VALIDATION_LINT:-flake8}"
    fi

    # Typecheck
    if [[ -f "pyproject.toml" ]] && grep -q "mypy" pyproject.toml 2>/dev/null; then
        VALIDATION_TYPECHECK="${VALIDATION_TYPECHECK:-mypy .}"
    fi
fi

# NOTE(jimmylee)
# Go projects
if [[ -f "go.mod" ]]; then
    echo "# Detected: Go project (go.mod)" >&2

    VALIDATION_TEST="${VALIDATION_TEST:-go test ./...}"
    VALIDATION_BUILD="${VALIDATION_BUILD:-go build ./...}"
    VALIDATION_LINT="${VALIDATION_LINT:-go vet ./...}"
fi

# =============================================================================
# Rust projects
# =============================================================================
if [[ -f "Cargo.toml" ]]; then
    echo "# Detected: Rust project (Cargo.toml)" >&2

    VALIDATION_TEST="${VALIDATION_TEST:-cargo test}"
    VALIDATION_BUILD="${VALIDATION_BUILD:-cargo build}"
    VALIDATION_LINT="${VALIDATION_LINT:-cargo clippy}"
fi

# =============================================================================
# Ruby projects
# =============================================================================
if [[ -f "Gemfile" ]]; then
    echo "# Detected: Ruby project (Gemfile)" >&2

    if [[ -f "Rakefile" ]] && grep -q "task.*:test" Rakefile 2>/dev/null; then
        VALIDATION_TEST="${VALIDATION_TEST:-bundle exec rake test}"
    elif [[ -d "spec" ]]; then
        VALIDATION_TEST="${VALIDATION_TEST:-bundle exec rspec}"
    elif [[ -d "test" ]]; then
        VALIDATION_TEST="${VALIDATION_TEST:-bundle exec rake test}"
    fi

    if grep -q "rubocop" Gemfile 2>/dev/null; then
        VALIDATION_LINT="${VALIDATION_LINT:-bundle exec rubocop}"
    fi
fi

# =============================================================================
# Java / Kotlin projects (Maven/Gradle)
# =============================================================================
if [[ -f "pom.xml" ]]; then
    echo "# Detected: Maven project (pom.xml)" >&2

    VALIDATION_TEST="${VALIDATION_TEST:-mvn test}"
    VALIDATION_BUILD="${VALIDATION_BUILD:-mvn compile}"
fi

if [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
    echo "# Detected: Gradle project" >&2

    VALIDATION_TEST="${VALIDATION_TEST:-./gradlew test}"
    VALIDATION_BUILD="${VALIDATION_BUILD:-./gradlew build}"
fi

# =============================================================================
# Makefile fallback
# =============================================================================
if [[ -f "Makefile" ]]; then
    echo "# Detected: Makefile" >&2

    if check_make_target "test" && [[ -z "$VALIDATION_TEST" ]]; then
        VALIDATION_TEST="make test"
    fi
    if check_make_target "build" && [[ -z "$VALIDATION_BUILD" ]]; then
        VALIDATION_BUILD="make build"
    fi
    if check_make_target "lint" && [[ -z "$VALIDATION_LINT" ]]; then
        VALIDATION_LINT="make lint"
    fi
    if check_make_target "check" && [[ -z "$VALIDATION_LINT" ]]; then
        VALIDATION_LINT="make check"
    fi
fi

# =============================================================================
# Output results
# =============================================================================
echo "VALIDATION_TEST=$VALIDATION_TEST"
echo "VALIDATION_BUILD=$VALIDATION_BUILD"
echo "VALIDATION_LINT=$VALIDATION_LINT"
echo "VALIDATION_TYPECHECK=$VALIDATION_TYPECHECK"

# Summary to stderr
if [[ -n "$VALIDATION_TEST" || -n "$VALIDATION_BUILD" || -n "$VALIDATION_LINT" || -n "$VALIDATION_TYPECHECK" ]]; then
    echo "# Validation commands detected" >&2
else
    echo "# No validation commands detected - validation will be skipped" >&2
fi
