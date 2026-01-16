#!/bin/bash
#
# NOTE(angeldev)
# Centralized constants for the www-agent system.
# All magic numbers and configuration values should be defined here
# for easy tuning and discoverability.

[[ -n "${_CONSTANTS_SH_LOADED:-}" ]] && return 0
_CONSTANTS_SH_LOADED=1

# =============================================================================
# LLM PROVIDER LIMITS
# =============================================================================

# Maximum output tokens for all LLM providers
# - Anthropic claude-opus-4-5: supports up to 16384 (32K with extended thinking)
# - OpenAI gpt-5.x: supports 16384+
export MAX_OUTPUT_TOKENS=16384

# =============================================================================
# CODEBASE ANALYSIS LIMITS
# =============================================================================

# Maximum characters of source code to include in deep analysis
# With 200K token context (Anthropic) and ~4 chars/token, we can use up to 800K chars
# We reserve ~40K tokens for system prompts, output, and overhead
# This gives us ~160K tokens = 640K chars for codebase content
export MAX_CODEBASE_CHARS=640000

# =============================================================================
# PR AND COMMIT LIMITS
# =============================================================================

# Maximum length for PR titles (human-readable limit, GitHub allows up to 256)
export MAX_PR_TITLE_LENGTH=128

# =============================================================================
# REVIEW CYCLE LIMITS
# =============================================================================

# Maximum number of full review cycles before giving up
export MAX_REVIEW_CYCLES=5

# Maximum fix attempts per persona per review cycle
export MAX_FIX_ATTEMPTS_PER_PERSONA=2

# Maximum retry attempts for applying code edits
export MAX_APPLY_RETRIES=2

# Maximum retry attempts for recoverable errors (API calls, etc.)
export MAX_RETRIES=3

# Maximum retry attempts for Engineer implementation
export MAX_ENGINEER_ATTEMPTS=3

# Maximum retry attempts for PR creation
export MAX_PR_ATTEMPTS=3

# =============================================================================
# API RATE LIMITING
# =============================================================================

# Default spacing between API requests (milliseconds)
export DEFAULT_REQUEST_SPACING_MS=500

# Longer spacing for thinking operations (milliseconds)
export THINKING_REQUEST_SPACING_MS=2000

# Engineer implementation spacing (milliseconds)
export ENGINEER_SPACING_MS=3000

# =============================================================================
# FILE READING LIMITS
# =============================================================================

# Maximum lines to read from a single file when providing context
export MAX_FILE_LINES=500

# =============================================================================
# CHUNKED EDIT CONFIGURATION
# =============================================================================

# NOTE(angeldev)
# Threshold for when to use chunked edit strategy (number of files)
export EDIT_CHUNK_THRESHOLD=5

# Number of files per chunk when using chunked edit strategy
export EDIT_CHUNK_SIZE=3

# =============================================================================
# COMMIT RETRY CONFIGURATION
# =============================================================================

# NOTE(angeldev)
# Maximum push retry attempts
export MAX_PUSH_RETRIES=3

# =============================================================================
# CONTEXT WINDOW MONITORING
# =============================================================================

# NOTE(angeldev)
# Approximate characters per token (for estimation)
export CHARS_PER_TOKEN=4

# Context window limits (tokens) - use full provider limits
export ANTHROPIC_CONTEXT_LIMIT=200000
export OPENAI_CONTEXT_LIMIT=128000

# Warning threshold (percentage of context before warning)
# Set high (95%) - only warn when truly near limit, not prematurely
export CONTEXT_WARNING_THRESHOLD=95

# Enable token debugging (set to "true" to see token estimates)
export DEBUG_TOKENS=false

# =============================================================================
# LARGE FILE HANDLING
# =============================================================================

# NOTE(angeldev)
# Threshold for large file handling in bytes (100KB)
export LARGE_FILE_THRESHOLD_BYTES=102400
