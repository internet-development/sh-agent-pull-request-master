## What Changed

- **Dependency version updates** in `tools/apply-edits/Cargo.toml`:
  - clap 4.4 → 4.5
  - tempfile 3.9 → 3.10
  - Other minor dependency bumps

- **README.md clarifications**:
  - Added jq ≥1.6 version requirement
  - Clarified dry-run behavior description
  - Updated atomic vs partial mode wording for clarity

- **Documentation addition**:
  - Added `tools/apply-edits/README.md` documenting existing CLI behavior

## What Did NOT Change

- **No CLI flags added, removed, or modified** - all existing flags remain: `--workdir`, `--stdin`, `--file`, `--dry-run`, `--partial`, `--max-lines`, `--format`
- **No subcommands changed** - `apply` and `read` remain unchanged
- **No default values changed** - `--max-lines` still defaults to 500, `--format` still defaults to "json"
- **No JSON output schema changes** - output structure remains: `success`, `applied`, `failed`, `edits[]` with `status`, `index`, `path`, `type`, `message` fields
- **No runtime or behavioral changes** to the apply-edits tool
