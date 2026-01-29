# apply-edits

A Rust CLI tool for applying targeted, atomic file edits. Used internally by `agent.sh` but can be used standalone for programmatic file modifications.

## Overview

`apply-edits` takes a JSON description of edits and applies them to files in a working directory. It's designed for reliability:

- **Atomic by default**: If any edit fails, all changes are rolled back
- **Precise matching**: Uses exact string matching with fuzzy fallback for helpful error messages
- **Indentation-aware**: Automatically handles minor indentation differences between search strings and file content

## Usage

```bash
# Apply edits from a JSON file
apply-edits apply --file edits.json --workdir /path/to/repo

# Apply edits from stdin
echo '{"edits": [...]}' | apply-edits apply --stdin --workdir /path/to/repo

# Dry-run mode (simulate without writing)
apply-edits apply --file edits.json --workdir /path/to/repo --dry-run

# Partial mode (continue on errors, non-atomic)
apply-edits apply --file edits.json --workdir /path/to/repo --partial
```

## Edit Types

| Type | Description |
|------|-------------|
| `replace` | Replace first occurrence of `search` with `replace` |
| `replace_all` | Replace all occurrences of `search` with `replace` |
| `insert_after` | Insert `content` after line containing `anchor` |
| `insert_before` | Insert `content` before line containing `anchor` |
| `insert_at_line` | Insert `content` at specific `line` number (1-indexed) |
| `create` | Create new file with `content` |
| `delete_file` | Delete the file |
| `delete_lines` | Delete lines from `start_line` to `end_line` (inclusive) |
| `delete_match` | Delete all lines containing `search` |
| `append` | Append `content` to end of file |
| `prepend` | Prepend `content` to beginning of file |

## JSON Format

```json
{
  "edits": [
    {
      "type": "replace",
      "path": "src/main.rs",
      "search": "fn old_name()",
      "replace": "fn new_name()"
    },
    {
      "type": "insert_after",
      "path": "src/lib.rs",
      "anchor": "use std::io;",
      "content": "use std::fs;"
    },
    {
      "type": "create",
      "path": "src/new_module.rs",
      "content": "// New module\npub fn hello() {}\n"
    }
  ],
  "commit_message": "refactor: rename function and add module",
  "summary": "Renamed old_name to new_name and added new_module"
}
```

## Modes

### Atomic Mode (Default)

All edits succeed or all are rolled back. Use this when edits are interdependent.

```bash
apply-edits apply --file edits.json --workdir ./repo
```

### Partial Mode

Continue applying edits even if some fail. Successful edits are kept.

```bash
apply-edits apply --file edits.json --workdir ./repo --partial
```

### Dry-Run Mode

Simulate edits without writing to disk. Shows what would happen.

```bash
apply-edits apply --file edits.json --workdir ./repo --dry-run
```

## Output

### Human-Readable (stderr)

Progress and status information is written to stderr:

```
apply-edits v0.1.0
Working directory: /path/to/repo
🔒 ATOMIC MODE: Any failure will roll back all changes

Processing 3 edit(s)...

[1/3] replace src/main.rs
      ✓ Replaced 1 occurrence (line 42)
[2/3] insert_after src/lib.rs
      ✓ Inserted after anchor at line 5
[3/3] create src/new_module.rs
      ✓ Created file (2 lines, 28 bytes)

✅ 3 edit(s) applied, 0 failed
```

### JSON (stdout)

Structured result is written to stdout:

```json
{
  "success": true,
  "applied": 3,
  "failed": 0,
  "edits": [
    {"status": "ok", "index": 0, "path": "src/main.rs", "type": "replace", "message": "Replaced 1 occurrence (line 42)"},
    {"status": "ok", "index": 1, "path": "src/lib.rs", "type": "insert_after", "message": "Inserted after anchor at line 5"},
    {"status": "ok", "index": 2, "path": "src/new_module.rs", "type": "create", "message": "Created file (2 lines, 28 bytes)"}
  ]
}
```

## Error Handling

When an edit fails, the output includes helpful diagnostics:

- `error`: Machine-readable error code (e.g., `search_not_found`, `file_not_found`)
- `message`: Human-readable description
- `search_preview`: The search string that failed (truncated)
- `closest_matches`: Similar content found in the file with line numbers and similarity scores
- `hint`: Suggested action to resolve the issue

## Reading Files

`apply-edits` can also read files with line numbers:

```bash
# Read a single file
apply-edits read --file src/main.rs --workdir ./repo

# Read multiple files
apply-edits read --files "src/main.rs,src/lib.rs" --workdir ./repo

# Output in prompt format (for LLM context)
apply-edits read --file src/main.rs --workdir ./repo --format prompt
```
