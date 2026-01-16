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

## Questions

If you have questions ping me on Twitter, [@wwwjim](https://www.twitter.com/wwwjim). Or you can ping [@internetxstudio](https://x.com/internetxstudio).
