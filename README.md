# SH-AGENT-PULL-REQUEST-MASTER

Multi-persona agent for submitting a Pull Request to your favorite GitHub repository you have access to.

All you need is Bash 3.2, Rust and some API keys.

## How It Works

Check out [AGENTS.md](https://github.com/internet-development/sh-agent-pull-request-master) for a full breakdown.

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env

# YOU MUST FILL YOUR API KEYS AND GITHUB TOKEN

# 2. Check everything is set up
./agent.sh status

# 3. Test all integrations (dry run)
./agent.sh dry-run

# 4. Write your goal in .directive
echo "Lets add a Footer the codebase that is simple that doesn't add complication but solves a problem the codebase missed. You must follow the codebases conventions exactly, the codebase adheres to a specific style." > .directive

# 5. Run the agent
./agent.sh run
```

## The Directive File

The agent reads its goal from the `.directive` file in the repository root. This file should contain a clear, actionable objective:

```bash
# Example .directive contents:
Lets add a Footer the codebase that is simple that doesn't add complication but solves a problem the codebase missed. You must follow the codebases conventions exactly, the codebase adheres to a specific style.
```

To change what the agent works on, edit the `.directive` file directly. The agent will read this file each time it runs.

## Commands

| Command | Description |
|---------|-------------|
| `./agent.sh run` | Run agent using `.directive` file |
| `./agent.sh dry-run` | Test full flow without executing changes |
| `./agent.sh new` | Clear current session |
| `./agent.sh status` | Show environment and session status |
| `./agent.sh test-models` | Test API connections only |
| `./agent.sh clear-context` | Clear all context and state |

## Environment Variables

Create a `.env` file with:

```bash
API_KEY_ANTHROPIC=...
GITHUB_TOKEN=...
GITHUB_REPO_AGENTS_WILL_WORK_ON=owner/repo
GITHUB_USERNAME=...
API_KEY_OPEN_AI=...
API_KEY_GOOGLE_CUSTOM_SEARCH=...
GOOGLE_CUSTOM_SEARCH_ID=...
```

**Important:** `GITHUB_REPO_AGENTS_WILL_WORK_ON` specifies the repository where the agent will create PRs, NOT this agent's repository. For example, if you want the agent to work on `internet-development/nextjs-sass-starter`, set:

```bash
GITHUB_REPO_AGENTS_WILL_WORK_ON=internet-development/nextjs-sass-starter
```

## Prerequisites

- `bash` (3.2+)
- `rust` for the Engineer
- `curl` for API requests (standard on macOS/Linux)
- `git` for version control operations
- `jq` for JSON parsing (required)

## GitHub Token Permissions

Your `GITHUB_TOKEN` needs these permissions on the target repository:

- `repo` - Full control of private repositories
- `write:discussion` - Write access to discussions (for PR comments)

If working on a public repo you don't own, you'll need to fork it first and set `GITHUB_REPO_AGENTS_WILL_WORK_ON` to your fork.

## Safety Guarantees

The `apply-edits` tool provides strong safety guarantees by default:

- **Atomic Mode (default)**: All edits succeed or none are applied. If any edit fails, all changes are rolled back automatically.
- **No Partial Corruption**: Your repository is never left in an inconsistent state.
- **Dry-Run Mode**: Simulate all changes without touching disk using `--dry-run`. Validates that all edits would succeed before any changes are made.
- **Partial Mode (opt-in)**: Use `--partial` to continue applying edits even if some fail (non-atomic).

### Behavior Clarifications (v1.x)

The following behaviors are guaranteed and enforced by integration tests (see `tools/apply-edits/src/` test modules):

1. **Dry-run validation**: `--dry-run` performs full validation of all edits against actual file contents. It reports exactly what would happen without modifying any files.
2. **Atomic rollback**: In default (atomic) mode, if edit N fails, all previously successful edits (1 through N-1) are rolled back to their original state.
3. **Partial continuation**: With `--partial`, failed edits are skipped but successful edits are preserved. The exit code is non-zero if any edit fails.
4. **JSON output stability**: The JSON output schema includes `success` (boolean), `applied` (number), `failed` (number), and `edits` (array). Each edit entry includes `status`, `index`, `path`, and `type`. Error entries additionally include `error`, `message`, and contextual fields like `hint` and `closest_matches`.

## Mental Model

Think of `apply-edits` as a transactional patch engine:

1. **Read** - Load files that will be modified (use `apply-edits read --file <path> --workdir .` to inspect files)
2. **Validate** - Check that all search strings and anchors exist exactly as specified
3. **Backup** - Store original content for potential rollback
4. **Apply** - Execute edits in order
5. **Rollback or Commit** - On failure, restore originals; on success, keep changes

The `read` subcommand supports both `--file` for a single file and `--files` for comma-separated lists, with optional `--max-lines` and `--format` (json or prompt) flags.

## Questions

If you have questions ping me on Twitter, [@wwwjim](https://www.twitter.com/wwwjim). Or you can ping [@internetxstudio](https://x.com/internetxstudio).
