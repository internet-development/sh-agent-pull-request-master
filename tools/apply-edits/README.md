# apply-edits

A Rust CLI tool for applying targeted code edits with multi-line support, indentation-aware matching, and Atomic mode execution guarantees.

## Installation

```bash
cd tools/apply-edits
cargo build --release
```

The binary will be at `target/release/apply-edits`.

## Commands

### apply

Apply edits from JSON input.

```bash
apply-edits apply --workdir /path/to/repo --stdin < edits.json
apply-edits apply --workdir /path/to/repo --file edits.json
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--workdir` | Working directory (repository root) - required |
| `--stdin` | Read JSON from stdin |
| `--file` | Path to JSON file containing edits |
| `--dry-run` | Show what would happen without making changes |
| `--partial` | Continue on errors (non-atomic mode, also called partial mode) |

**Default Behavior (Atomic Mode):**

By default, edits are applied atomically. If any edit fails, all changes are rolled back and the repository is restored to its original state.

**Partial Mode:**

With `--partial`, the tool continues applying remaining edits even if some fail. This is non-atomic—successful edits are kept even when others fail.

**Dry-Run Mode:**

With `--dry-run`, no files are modified. The tool simulates each edit and reports what would happen, using the same validation logic as real execution.

### read

Read files with line numbers for context.

```bash
apply-edits read --workdir /path/to/repo --file src/main.rs
apply-edits read --workdir /path/to/repo --files "src/lib.rs,src/main.rs" --format prompt
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--workdir` | Working directory (repository root) - required |
| `--file` | Single file to read |
| `--files` | Comma-separated list of files to read |
| `--max-lines` | Maximum lines to read per file (default: 500) |
| `--format` | Output format: `json` (default) or `prompt` |

## Edit Types

| Type | Description |
|------|-------------|
| `replace` | Replace first occurrence of search string |
| `replace_all` | Replace all occurrences of search string |
| `insert_after` | Insert content after line containing anchor |
| `insert_before` | Insert content before line containing anchor |
| `insert_at_line` | Insert content at specific line number (1-indexed) |
| `create` | Create a new file with content |
| `delete_file` | Delete a file |
| `delete_lines` | Delete lines in range (1-indexed, inclusive) |
| `delete_match` | Delete all lines containing search string |
| `append` | Append content to end of file |
| `prepend` | Prepend content to beginning of file |

## JSON Input Format

```json
{
  "edits": [
    {
      "type": "replace",
      "path": "src/main.rs",
      "search": "old code",
      "replace": "new code"
    },
    {
      "type": "insert_after",
      "path": "src/lib.rs",
      "anchor": "use std::io;",
      "content": "use std::fs;"
    },
    {
      "type": "create",
      "path": "src/new_file.rs",
      "content": "// New file content"
    }
  ],
  "commit_message": "feat: add new feature",
  "summary": "Optional summary of changes"
}
```

**Field Aliases:**

For `insert_after` and `insert_before`, the anchor field accepts these aliases:
- `anchor`, `search`, `match`, `after`, `before`, `pattern`, `at`, `location`

## Output

**Human-readable output** goes to stderr with colored status indicators.

**JSON result** goes to stdout:

```json
{
  "success": true,
  "applied": 3,
  "failed": 0,
  "edits": [
    {
      "status": "ok",
      "index": 0,
      "path": "src/main.rs",
      "type": "replace",
      "message": "Replaced 1 occurrence (line 42)"
    }
  ]
}
```

**Outcome Statuses:**

| Status | Meaning |
|--------|--------|
| `ok` | Edit applied successfully |
| `warning` | Edit succeeded with caveats (e.g., no matches for delete_match) |
| `error` | Edit failed |

## Indentation Handling

The tool automatically handles indentation differences between search strings and file content:

1. **Exact match** is always tried first
2. If exact match fails, **normalized matching** compares content ignoring leading whitespace
3. When a normalized match is found, the replacement preserves the file's original indentation

This allows edits to succeed even when the search string has different indentation than the actual file content.

## Error Diagnostics

When a search or anchor string is not found, the tool provides:

- **Search preview**: The string that was searched for
- **Closest matches**: Similar content found in the file with line numbers and similarity percentages
- **Hints**: Suggestions for resolving the issue

## Exit Codes

| Code | Meaning |
|------|--------|
| 0 | All edits succeeded |
| 1 | One or more edits failed |

## Verification Notes

### Test Verification

All tests pass when running `cargo test` in `tools/apply-edits/`.

### Security Audit

`cargo audit` was run on 2025-01 using cargo-audit 0.21 against the current dependency graph (clap 4.5, tempfile 3.10, etc.). No high or critical vulnerabilities were found. To verify, run `cargo audit` from the `tools/apply-edits/` directory.

### CLI/JSON Stability

After dependency version bumps (clap 4.4 → 4.5, etc.):
- All existing CLI flags remain unchanged: `--workdir`, `--stdin`, `--file`, `--dry-run`, `--partial`, `--max-lines`, `--format`
- All subcommands remain unchanged: `apply`, `read`
- Default values unchanged: `--max-lines` defaults to 500, `--format` defaults to "json"
- JSON output schema unchanged: `success`, `applied`, `failed`, `edits[]` with `status`, `index`, `path`, `type`, `message` fields

### Documentation Addition Justification

This README is documentation-only. It describes existing behavior without introducing new flags, subcommands, or output formats. All documented features existed prior to this file's creation.
