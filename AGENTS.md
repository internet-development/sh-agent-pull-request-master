# AGENTS.md

This document provides critical context for AI agents working on this codebase. Read this file completely before making changes.

## The Canonical Loop

**See [LOOP.md](./LOOP.md) for the authoritative workflow definition.**

LOOP.md is the source of truth for:
- The complete workflow phases (Brainstorm → Plan → Implement → Review → Debug → Handoff)
- TDD requirements and the Iron Laws
- Verification requirements
- Systematic debugging process
- Review cycles and handoff procedures

This file (AGENTS.md) contains project-specific details that complement LOOP.md.

---

## What This Project Does

This agent takes a directive (a goal written in `.directive`) and executes a multi-phase process that results in a Pull Request on a `GITHUB_REPO_AGENTS_WILL_WORK_ON`. The PR goes through 1-5 review cycles where multiple AI personas evaluate and improve the code. Between each review, there are potential code commits that increase the chance of approval. The process ends with a handoff to a human codebase owner who makes the final merge decision.

---

## The Iron Laws (Summary)

These are explained in detail in LOOP.md. Memorize them:

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
3. NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
4. EVIDENCE BEFORE CLAIMS, ALWAYS
```

---

## Two Output Streams

This is a critical distinction. The agent produces two completely separate outputs:

### Terminal Log (Developer-Facing)

The terminal shows detailed operational logging:
- Colored output with persona-specific styling (diamonds, background colors)
- Token usage and API receipts
- Phase markers (PLANNING, REVIEW CYCLE 1, COMPLETE)
- Error messages and debugging information
- LLM vendor indicators (Anthropic, OpenAI, Local)

**This is NOT seen by anyone except developers running the agent locally.**

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

---

## The Internal Monologue

### Philosophy

All GitHub comments should read as ONE cohesive internal reflection from a single developer thinking through a code review. They should NOT feel like separate disconnected reviews from different angles or personas.

The goal is to create the experience of watching someone think through a code review out loud. Each comment builds on the previous ones. The reviewer references earlier observations. The conversation flows naturally.

### How It Works Technically

1. **Structured Review**: Each persona produces structured JSON output with their review findings

2. **Humanization**: The `humanize_for_github()` function in `lib/providers.sh` transforms structured reviews into natural prose using GPT-5

3. **Comment Accumulation**: Previous humanized comments are stored in a file (`$STATE_DIR/humanized_comments.txt`) that survives subshell boundaries

4. **Context Passing**: Each new comment receives ALL previous comments as context, with instructions to continue the conversation

5. **Continuity Prompting**: The humanization prompt explicitly instructs the LLM to:
   - Continue the conversation naturally
   - Reference or build on earlier observations
   - Feel like the next natural thought in the reflection
   - Maintain the same voice and tone throughout

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

---

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

This table uses `--skip-humanize` flag to preserve markdown formatting.

---

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

---

## Key Files

| File | Purpose |
|------|---------|
| `LOOP.md` | **Canonical workflow definition** - the source of truth for phases and iron laws |
| `skills/` | **Mandatory workflow skills** - TDD, debugging, verification, review patterns |
| `agent.sh` | Entry point - handles commands like `run`, `dry-run`, `status` |
| `lib/persona.sh` | Main orchestration - contains `execute_plan()` and all workflow logic |
| `lib/planning.sh` | Planning phase - clone, analyze, research, requirements synthesis |
| `lib/implementation.sh` | Implementation - Engineer code generation and application |
| `lib/review.sh` | Review cycles - persona reviews, feedback synthesis, fix iterations |
| `lib/providers.sh` | LLM API calls - Anthropic, OpenAI, plus `humanize_for_github()` |
| `lib/logging.sh` | Terminal output styling - colors, icons, phase markers |
| `lib/memory.sh` | Task context and state management |
| `lib/config.sh` | Configuration loading, persona/model mapping |
| `adapters/github-comment-pr.sh` | Posts comments to GitHub with humanization |
| `adapters/github-create-pr.sh` | Creates pull requests |
| `adapters/github-commit-changes.sh` | Commits and pushes code |
| `adapters/apply-edits.sh` | Applies targeted code edits |
| `.personality` | Voice and tone definition for all humanized output |
| `.directive` | User's goal - the input that drives everything |

---

## Skills (Mandatory Workflows)

**See [skills/](./skills/) directory for mandatory workflows.**

Skills are not suggestions - if a skill applies to your task, you MUST use it.

| Skill | When to Use |
|-------|-------------|
| [test-driven-development](./skills/test-driven-development.md) | Before writing ANY implementation code |
| [systematic-debugging](./skills/systematic-debugging.md) | When encountering ANY bug or test failure |
| [verification-before-completion](./skills/verification-before-completion.md) | Before claiming ANY work is complete |
| [two-stage-review](./skills/two-stage-review.md) | When reviewing ANY implementation |
| [brainstorming](./skills/brainstorming.md) | Before ANY creative work (features, components) |

---

## Directory Structure

```
www-agent/
├── LOOP.md                        # Canonical workflow definition (READ THIS)
├── AGENTS.md                      # Project-specific context (this file)
├── agent.sh                       # Entry point
├── .directive                     # User's goal (you edit this)
├── .personality                   # Agent's voice definition
├── .workrepo/                     # Cloned target repos (gitignored)
├── .context/                      # Session context (gitignored)
├── .state/                        # Session state including humanized_comments.txt (gitignored)
├── lib/                           # Core libraries
├── adapters/                      # GitHub/git operation scripts
├── personas/                      # Persona definitions (markdown + JSON)
├── skills/                        # Mandatory workflow skills (READ THESE)
├── workflows/                     # Workflow checklists
└── configs/                       # Model configuration
```

---

## Rules When Modifying This Codebase

1. **Follow LOOP.md** - The workflow, TDD requirements, verification requirements, and debugging process are all defined there. Don't deviate.

2. **NEVER break the internal monologue** - Comments must maintain continuity across all persona reviews. The file-based persistence (`HUMANIZED_COMMENTS_FILE`) is critical.

3. **The `.personality` file defines the agent's voice** - Changes here affect ALL humanized output. Do not modify without careful consideration.

4. **Terminal logging is for developers; GitHub output is the product** - Keep these concerns separate. Don't mix debugging output with user-facing content.

5. **The decision table emoji meanings are important** - Observers rely on ✅/⏭️ to understand what was incorporated vs skipped.

6. **Preserve the review cycle structure** - The loop of review → feedback → fix → commit → re-review is core to how the agent improves code quality.

7. **The agent does NOT auto-merge** - Human handoff is intentional. The human codebase owner always makes the final merge decision.

8. **Comment humanization uses GPT** - This is intentional for quality. The `humanize_for_github()` function is performance-sensitive.

9. **Subshell boundaries matter** - The file-based comment persistence exists because bash subshells (`$(...)`) don't share variable state with parent shells.

---

## Patterns Discovered (Update This Section)

As you work on this codebase, add reusable patterns here:

- When modifying persona logic, also update the corresponding persona definition in `personas/`
- Tests require the target repo to be cloned in `.workrepo/`
- Environment variables are loaded from `.env` via `lib/config.sh`
- All LLM calls go through `lib/providers.sh` - don't call APIs directly

---

## Credits

This workflow incorporates patterns from:
- [obra/superpowers](https://github.com/obra/superpowers) - TDD, systematic debugging, verification-before-completion, subagent-driven development
- [snarktank/ralph](https://github.com/snarktank/ralph) - Fresh context per iteration, progress tracking, small task granularity
