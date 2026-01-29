# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2025-01-13

### Added
- Atomic edit transactions with automatic rollback on failure
- Dry-run mode for safe preview of changes without modifying files
- Batch optimization for multiple edits to the same file
- Auto-correction suggestions for common edit failures (indentation, whitespace, line endings)
- Memory-mapped I/O for large files (>100KB) to reduce memory pressure
- Indentation-aware matching that handles LLM indentation mismatches gracefully

### Changed
- Updated core Rust dependencies for security and stability:
  - `memmap2` upgraded for improved safety and Windows compatibility
  - `serde` and `serde_json` upgraded for better error messages
  - `thiserror` upgraded for improved error formatting
  - `clap` upgraded for CLI parsing fixes
  - `strsim` upgraded for fuzzy matching improvements
  - `colored` upgraded for better terminal detection
  - `tempfile` upgraded for test reliability

### Fixed
- Improved error messages with closest-match hints when edits fail
- Better handling of files with mixed indentation styles

### Notes
- **No breaking changes** - all CLI flags, JSON schemas, and default behaviors remain unchanged
- Edits are atomic by default; use `--partial` flag for non-atomic mode
- Human-readable output remains on stderr, machine-readable JSON on stdout

### Security
- Path resolution note: all paths are resolved relative to `workdir`. Paths containing `../` may modify files outside the repository if explicitly provided.
