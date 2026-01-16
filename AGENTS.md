# AGENTS.md

This document provides critical context for AI agents working on this codebase. Read this file completely before making changes.

## What This Project Does

This agent takes a directive (a goal written in `.directive`) and executes a multi-phase process that results in a Pull Request on a `GITHUB_REPO_AGENTS_WILL_WORK_ON`. The PR goes through 1-5 review cycles where multiple AI personas evaluate and improve the code. Between each review, there are potential code commits that increase the chance of approval. The process ends with a handoff to a human codebase owner who makes the final merge decision.

## The Core Loop

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PHASE 1: PLANNING                               │
│  1. Clone target repository to .workrepo/                                   │
│  2. Deep codebase analysis (reads ALL source files)                         │
│  3. Director creates execution plan                                          │
│  4. Web research via Google Custom Search (if configured, and asked for)     │
│  5. Gather input from all personas                                          │
│  6. Director synthesizes requirements                                        │
│  7. Post decision table to PR (what's incorporated vs skipped)              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 2: IMPLEMENTATION                            │
│  1. Create feature branch                                                    │
│  2. Engineer implements changes up to three attempts                         │
│  3. Apply code changes with automatic retry for failed edits                │
│  4. Pre-commit analysis and message generation                              │
│  5. Commit and push changes                                                  │
│  6. Create Pull Request                                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PHASE 3: REVIEW CYCLES                               │
│                                                                              │
│  For each cycle (max 5 iterations):                                         │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ Project Manager Review (up to 2 fix attempts)                     │    │
│    │   → If NEEDS_WORK: Director synthesizes → Engineer fixes → Commit │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ Technical Writer Review (up to 2 fix attempts)                    │    │
│    │   → If NEEDS_WORK: Director synthesizes → Engineer fixes → Commit │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ Researcher Review (if enabled, up to 2 fix attempts)              │    │
│    │   → If NEEDS_WORK: Director synthesizes → Engineer fixes → Commit │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ If ALL approved → Director Final Review                           │    │
│    │   → If APPROVE: Submit GitHub approval with "LGTM"                │    │
│    │   → Break loop                                                     │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            HUMAN HANDOFF                                     │
│  PR is ready for human codebase owner to review and merge                   │
│  Agent does NOT auto-merge - human makes final decision                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key insight**: Between each review, there are potential code commits. Each fix commit improves the code and increases the chance of the entire cycle being approved.

## Two Output Streams

This is a critical distinction. The agent produces two completely separate outputs:

### Terminal Log (Developer-Facing)

The terminal shows detailed operational logging:
- Colored output with persona-specific styling (diamonds, background colors)
- Token usage and API receipts
- Logging library utility methods are used to improve appearance
- Phase markers (PLANNING, REVIEW CYCLE 1, COMPLETE)
- Error messages and debugging information
- LLM vendor indicators (Anthropic, OpenAI, Local)

**This is NOT seen by anyone except developers running the agent locally.**

The terminal log exists for debugging and observing what's happening internally.

### GitHub PR + Comments (The Deliverable)

The GitHub output is what humans see and judge the agent by:
- The Pull Request title and description
- Review comments written as internal monologue
- Decision tables showing what was incorporated vs skipped
- Commit messages
- Emoji reactions as read receipts

**This is the product. This is what observers see.**

The GitHub output must be:
- Human-readable and natural
- One cohesive voice throughout
- Professional but thoughtful
- Easy to follow and understand
- Follows the personality in `.personality`

## The Internal Monologue

This section is critical. Read it carefully.

### Philosophy

All GitHub comments should read as ONE cohesive internal reflection from a single developer thinking through a code review. They should NOT feel like separate disconnected reviews from different angles or personas.

The goal is to create the experience of watching someone think through a code review out loud. Each comment builds on the previous ones. The reviewer references earlier observations. The conversation flows naturally.

### Why This Matters

When an observer reads the PR comments, they should feel like they're following one person's thought process as they carefully review the code. Not a committee. Not multiple reviewers. One dedicated developer who cares deeply about getting it right.

This is what makes the agent's output feel human and trustworthy.

### How It Works Technically

1. **Structured Review**: Each persona produces structured JSON output with their review findings

2. **Humanization**: The `humanize_for_github()` function in `lib/providers.sh` transforms structured reviews into natural prose using GPT-5

3. **Comment Accumulation**: Previous humanized comments are stored in a file (`$STATE_DIR/humanized_comments.txt`) that survives subshell boundaries. This will be deleted for each new session.

4. **Context Passing**: Each new comment receives ALL previous comments as context, with instructions to continue the conversation

5. **Continuity Prompting**: The humanization prompt explicitly instructs the LLM to:
   - Continue the conversation naturally
   - Reference or build on earlier observations
   - Feel like the next natural thought in the reflection
   - Maintain the same voice and tone throughout

### What Good Comments Sound Like

```
I've been through this carefully, and I'm feeling good about the overall direction. 
The footer component slots in cleanly without disrupting the existing layout system.

Building on what I noted earlier about the styling approach - the way this uses 
the existing color tokens is exactly right. No new variables, no special cases, 
just consistent application of what's already there.

One thing I want to call out: the error handling in the API integration is solid. 
I checked the edge cases and they're covered. This is the kind of attention to 
detail that makes code maintainable.
```

### What Bad Comments Sound Like

```
REVIEW FROM PROJECT MANAGER:
- Requirements met: Yes
- Scope adherence: Good
- Issues: None

---

REVIEW FROM TECHNICAL WRITER:
- Naming: Acceptable
- Documentation: Adequate
- Clarity: Good
```

The bad example feels robotic, disconnected, and obviously machine-generated. Each section starts fresh with no connection to what came before.

### Key Files for Internal Monologue

| File | Purpose |
|------|---------|
| `lib/providers.sh` | Contains `humanize_for_github()` - the transformation function (uses GPT-5) |
| `lib/humanize.sh` | Comment accumulation: `append_humanized_comment()`, `get_accumulated_comments()`, `reset_humanized_comments()` |
| `.personality` | Defines the voice and tone (DO NOT CHANGE without careful consideration) |
| `adapters/github-comment-pr.sh` | Posts comments to GitHub, handles humanization flow |

### Rules for the Internal Monologue

1. **NEVER** break comment continuity - each comment must be aware of previous ones
2. **NEVER** reveal multiple personas or "review angles" in GitHub output
3. **ALWAYS** maintain first-person voice ("I've checked...", "I noticed...")
4. **ALWAYS** show reasoning process, not just conclusions
5. The `.personality` file is sacred - it defines the agent's voice across all comments

## The Decision Table

When the Director synthesizes suggestions from all personas, a markdown table is posted to the PR showing what was incorporated vs skipped:

```markdown
| Decision | Reason |
| --- | --- |
| ✅ Add footer component | Addresses the missing footer requirement |
| ✅ Use existing color scheme | Already part of existing patterns |
| ⏭️ Refactor header | Skipping (side effect) - Out of scope |
| ⏭️ Add dark mode | Skipping (side effect) - Not in directive |
```

### Emoji Meanings

| Emoji | Meaning |
|-------|---------|
| ✅ | Incorporated - this suggestion will be implemented |
| ⏭️ | Skipped - intentionally not implementing (out of scope, side effect) |
| ❓ | Unknown decision type |

This table uses `--skip-humanize` flag to preserve markdown formatting (tables shouldn't be humanized into prose).

## Personas

| Persona | Role | Provider | Key Focus |
|---------|------|----------|-----------|
| **Director** | Planning, synthesis, final approval | GPT | Coordinates everything, makes final call |
| **Engineer** | Code implementation | Claude (Opus) | Writes actual code changes |
| **Project Manager** | Requirements validation | GPT | Ensures implementation matches directive exactly |
| **Technical Writer** | Language and clarity | GPT | Naming, semantic consistency, error messages |
| **Researcher** | Best practices | GPT | Security, performance, web research |

### Persona Output Format

Each persona outputs structured JSON:

```json
{
  "decision": "APPROVE | NEEDS_WORK | COMMENT",
  "summary": "One sentence overview",
  "issues": ["List of specific issues"],
  "whats_good": ["List of positive observations"],
  "next_cycle_prompt": "Instructions for Engineer if NEEDS_WORK"
}
```

This structured output is then humanized before posting to GitHub.

## Key Files

| File | Purpose |
|------|---------|
| `agent.sh` | Entry point - handles commands like `run`, `dry-run`, `status` |
| `lib/persona.sh` | Main orchestration - contains `execute_plan()` and all workflow logic |
| `lib/providers.sh` | LLM API calls - Anthropic, OpenAI, Ollama, plus `humanize_for_github()` |
| `lib/logging.sh` | Terminal output styling - colors, icons, phase markers |
| `lib/memory.sh` | Task context and state management |
| `lib/config.sh` | Configuration loading, persona/model mapping |
| `adapters/github-comment-pr.sh` | Posts comments to GitHub with humanization |
| `adapters/github-create-pr.sh` | Creates pull requests |
| `adapters/github-commit-changes.sh` | Commits and pushes code |
| `adapters/apply-edits.sh` | Applies targeted code edits |
| `.personality` | Voice and tone definition for all humanized output |
| `.directive` | User's goal - the input that drives everything |

## Directory Structure

```
www-agent/
├── agent.sh                    # Entry point
├── .directive                  # User's goal (you edit this)
├── .personality                # Agent's voice definition
├── .workrepo/                  # Cloned target repos (gitignored)
├── .context/                   # Session context (gitignored)
├── .state/                     # Session state including humanized_comments.txt (gitignored)
├── lib/                        # Core libraries
├── adapters/                   # GitHub/git operation scripts
├── personas/                   # Persona definitions (markdown + JSON)
├── workflows/                  # Workflow checklists
└── configs/                    # Model configuration
```

## Rules When Modifying This Codebase

1. **NEVER break the internal monologue** - Comments must maintain continuity across all persona reviews. The file-based persistence (`HUMANIZED_COMMENTS_FILE`) is critical.

2. **The `.personality` file defines the agent's voice** - Changes here affect ALL humanized output. Do not modify without careful consideration.

3. **Terminal logging is for developers; GitHub output is the product** - Keep these concerns separate. Don't mix debugging output with user-facing content.

4. **The decision table emoji meanings are important** - Observers rely on ✅/⏭️ to understand what was incorporated vs skipped.

5. **Preserve the review cycle structure** - The loop of review → feedback → fix → commit → re-review is core to how the agent improves code quality.

6. **The agent does NOT auto-merge** - Human handoff is intentional. The human codebase owner always makes the final merge decision.

7. **Comment humanization uses GPT** - This is intentional for quality. The `humanize_for_github()` function is performance-sensitive.

8. **Subshell boundaries matter** - The file-based comment persistence exists because bash subshells (`$(...)`) don't share variable state with parent shells.
