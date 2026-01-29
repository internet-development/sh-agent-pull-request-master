# SH-AGENT-PULL-REQUEST-MASTER

Multi-persona agent for submitting a Pull Request to your favorite GitHub repository you have access to.

All you need is Bash 3.2, Rust and some API keys.

## Conceptual Overview

This project is a **multi-persona AI agent** that automates the process of creating pull requests. Here's how the pieces fit together:

- **`agent.sh`** is the main entry point. It orchestrates the entire workflow: reading your goal, planning changes, applying edits, and creating a PR.
- **`apply-edits`** is an internal Rust tool that `agent.sh` uses to make precise, targeted file modifications. You don't run it directly unless you're embedding it in your own tooling.
- **Personas** (in `personas/`) define different perspectives the agent uses during planning and review (e.g., Engineer, Researcher, Technical Writer).
- **Workflows** (in `workflows/`) describe multi-step processes like code review or solution research.
- **Adapters** (in `adapters/`) handle interactions with external systems (Git, GitHub API, file operations).

## Who This Is For

- **End users**: Run `./agent.sh run` to have the agent create PRs based on your `.directive` file.
- **Contributors**: Modify personas, workflows, or adapters to customize agent behavior.
- **Tool consumers**: Use `apply-edits` directly if you need programmatic, atomic file editing in your own pipelines.

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

## What Happens When You Run `./agent.sh run`

1. **Reads** your `.directive` file to understand the goal
2. **Plans** the changes needed, consulting multiple personas for different perspectives
3. **Applies** edits to files using the `apply-edits` tool (atomic by default—failures roll back)
4. **Commits** changes to a new branch
5. **Creates** a pull request on GitHub

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

> ⚠️ **Fine-Grained Tokens (Recommended)**: GitHub is moving toward fine-grained personal access tokens. If using a fine-grained PAT, ensure it has:
> - Repository access for your target repo
> - Read/Write permissions for: Contents, Pull requests, and Metadata
>
> Classic tokens with `repo` scope still work but may see reduced support in the future.

## Glossary

| Term | Definition |
|------|------------|
| `.directive` | A file containing your goal for the agent. Plain text describing what you want changed. |
| `persona` | A defined perspective the agent adopts during planning or review (e.g., Engineer, Researcher). |
| `workflow` | A multi-step process template (e.g., `review-pull-request.md`, `write-code.md`). |
| `adapter` | A shell script that interfaces with external systems (Git, GitHub API, filesystem). |
| `edit` | A single file modification operation (replace, insert, delete, create). |
| `dry-run` | Mode where edits are simulated without writing to disk. |
| `atomic` | Default mode where any edit failure rolls back all changes in the batch. |
| `partial` | Mode where edit failures don't roll back; successful edits are kept. |

## Versioning

This project follows [SemVer](https://semver.org/). CLI flags, environment variables, and JSON edit formats are considered public API.

## Security

- API keys are never logged or included in error output
- Dry-run mode guarantees no filesystem writes
- Atomic mode ensures partial failures leave no corrupted state

## Questions

If you have questions ping me on Twitter, [@wwwjim](https://www.twitter.com/wwwjim). Or you can ping [@internetxstudio](https://x.com/internetxstudio).
