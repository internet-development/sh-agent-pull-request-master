# LOOP.md - The Canonical Workflow Loop

This is the **source of truth** for the agent's workflow. AGENTS.md references this file for the authoritative loop definition.

## The Iron Laws

Before anything else, internalize these non-negotiable principles:

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
3. NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
4. EVIDENCE BEFORE CLAIMS, ALWAYS
```

Violating the letter of these rules is violating the spirit.

---

## Phase 0: Brainstorming (Before Code)

**Trigger:** Any creative work - features, components, modifications.

**Process:**
1. Read the `.directive` completely
2. Check current project state (files, docs, recent commits)
3. Ask clarifying questions **one at a time** (prefer multiple choice)
4. Propose 2-3 approaches with trade-offs
5. Lead with your recommendation and explain why
6. Present design in sections (200-300 words), validate each
7. Document validated design before implementation

**Key Principles:**
- One question at a time - don't overwhelm
- YAGNI ruthlessly - remove unnecessary features
- Explore alternatives before settling
- Be flexible - go back when something doesn't make sense

---

## Phase 1: Planning

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PHASE 1: PLANNING                               │
│                                                                              │
│  1. Clone target repository to .workrepo/                                   │
│  2. Deep codebase analysis (read ALL source files)                          │
│  3. Director creates execution plan                                          │
│  4. Web research via Google Custom Search (if configured)                    │
│  5. Gather input from all personas                                          │
│  6. Director synthesizes requirements                                        │
│  7. Post decision table to PR (what's incorporated vs skipped)              │
│                                                                              │
│  OUTPUT: Written plan with bite-sized tasks (2-5 min each)                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Task Granularity (Critical)

Each step is ONE action:
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement minimal code to make test pass" - step
- "Run tests and verify they pass" - step
- "Commit" - step

**Not acceptable:** "Implement the feature" (too big)

### Plan Document Format

Every task must have:
- **Files:** Exact paths to create/modify/test
- **Code:** Complete code in plan (not "add validation")
- **Commands:** Exact commands with expected output
- **Verification:** How to prove this step worked

---

## Phase 2: Implementation (TDD Cycle)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 2: IMPLEMENTATION                            │
│                                                                              │
│  For each task in the plan:                                                  │
│                                                                              │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  RED: Write failing test                                          │    │
│    │    → Run test, WATCH IT FAIL                                      │    │
│    │    → Confirm it fails for the right reason                        │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  GREEN: Write minimal code to pass                                │    │
│    │    → Run test, WATCH IT PASS                                      │    │
│    │    → No extra features, no "improvements"                         │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  REFACTOR: Clean up (tests stay green)                            │    │
│    │    → Remove duplication                                           │    │
│    │    → Improve names                                                 │    │
│    │    → Extract helpers if needed                                     │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  COMMIT: Atomic commit with clear message                         │    │
│    │    → feat: [Story ID] - [Story Title]                             │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  Create feature branch                                                       │
│  Apply code changes with automatic retry for failed edits                   │
│  Push changes                                                                │
│  Create Pull Request                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The TDD Iron Law

```
Write code before the test? DELETE IT. Start over.
```

**No exceptions:**
- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

### Verification Before Moving On

Before claiming ANY task complete:

1. **IDENTIFY:** What command proves this claim?
2. **RUN:** Execute the FULL command (fresh, complete)
3. **READ:** Full output, check exit code, count failures
4. **VERIFY:** Does output confirm the claim?
5. **ONLY THEN:** Make the claim

```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct" / "I'm confident"
```

---

## Phase 3: Review Cycles

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PHASE 3: REVIEW CYCLES                               │
│                                                                              │
│  For each cycle (max 5 iterations):                                         │
│                                                                              │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  SPEC COMPLIANCE REVIEW                                           │    │
│    │    → Does code match spec exactly?                                │    │
│    │    → Nothing missing? Nothing extra?                              │    │
│    │    → If issues: Fix → Re-review (don't skip re-review)           │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  CODE QUALITY REVIEW                                              │    │
│    │    → Is implementation well-built?                                │    │
│    │    → If issues: Fix → Re-review (don't skip re-review)           │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  PERSONA REVIEWS (Project Manager, Technical Writer, Researcher) │    │
│    │    → Each outputs structured JSON                                 │    │
│    │    → If NEEDS_WORK: Director synthesizes → Engineer fixes        │    │
│    │    → Commit after each fix                                        │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                  │                                          │
│                                  ▼                                          │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │  If ALL approved → Director Final Review                          │    │
│    │    → If APPROVE: Submit GitHub approval with "LGTM"              │    │
│    │    → Break loop                                                   │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Two-Stage Review (Critical)

**Order matters:**
1. First: Spec compliance (does it match requirements?)
2. Then: Code quality (is it well-built?)

**Never:**
- Skip reviews
- Proceed with unfixed issues
- Start quality review before spec compliance is ✅
- Accept "close enough" on spec compliance

### Review Loops

When reviewer finds issues:
1. Implementer fixes them
2. Reviewer reviews again
3. Repeat until approved
4. **Don't skip the re-review**

---

## Phase 4: Systematic Debugging (When Issues Arise)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SYSTEMATIC DEBUGGING                                 │
│                                                                              │
│  NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST                            │
│                                                                              │
│  Phase 1: Root Cause Investigation                                          │
│    → Read error messages carefully (they often contain the solution)        │
│    → Reproduce consistently                                                  │
│    → Check recent changes (git diff, commits)                               │
│    → Trace data flow to find where bad value originates                     │
│                                                                              │
│  Phase 2: Pattern Analysis                                                   │
│    → Find working examples in same codebase                                  │
│    → Compare against references (read completely, don't skim)               │
│    → Identify every difference, however small                               │
│                                                                              │
│  Phase 3: Hypothesis and Testing                                            │
│    → Form single hypothesis: "I think X because Y"                          │
│    → Test minimally (smallest possible change)                              │
│    → One variable at a time                                                  │
│                                                                              │
│  Phase 4: Implementation                                                     │
│    → Create failing test case FIRST                                         │
│    → Implement single fix (ONE change at a time)                            │
│    → Verify fix                                                              │
│                                                                              │
│  If 3+ fixes failed: STOP                                                    │
│    → Question the architecture                                               │
│    → Don't attempt Fix #4 without architectural discussion                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Red Flags - STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"

**ALL of these mean: STOP. Return to Phase 1.**

---

## Phase 5: Human Handoff

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            HUMAN HANDOFF                                     │
│                                                                              │
│  1. Verify tests pass (MANDATORY - run the command, see the output)         │
│  2. Present exactly 4 options:                                              │
│     - Merge back to base branch locally                                     │
│     - Push and create a Pull Request                                        │
│     - Keep the branch as-is (human handles later)                           │
│     - Discard this work                                                      │
│                                                                              │
│  PR is ready for human codebase owner to review and merge                   │
│  Agent does NOT auto-merge - human makes final decision                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## The Internal Monologue (GitHub Output)

All GitHub comments read as ONE cohesive internal reflection from a single developer. **Not** separate disconnected reviews.

### Rules:
1. **NEVER** break comment continuity - each comment aware of previous ones
2. **NEVER** reveal multiple personas in GitHub output
3. **ALWAYS** maintain first-person voice ("I've checked...", "I noticed...")
4. **ALWAYS** show reasoning process, not just conclusions

### Good Example:
```
I've been through this carefully, and I'm feeling good about the overall direction.
The footer component slots in cleanly without disrupting the existing layout system.

Building on what I noted earlier about the styling approach - the way this uses
the existing color tokens is exactly right. No new variables, no special cases,
just consistent application of what's already there.
```

### Bad Example:
```
REVIEW FROM PROJECT MANAGER:
- Requirements met: Yes

REVIEW FROM TECHNICAL WRITER:
- Naming: Acceptable
```

---

## Fresh Context Per Iteration

Each iteration spawns a **new instance** with clean context. Memory persists via:
- Git history (commits from previous iterations)
- `progress.txt` or `.state/` (learnings and context)
- `.directive` (the goal)
- AGENTS.md files (codebase patterns)

### Updating AGENTS.md Files

After completing work, check if edited files have learnings worth preserving:

**Good additions:**
- "When modifying X, also update Y to keep them in sync"
- "This module uses pattern Z for all API calls"
- "Tests require the dev server running on PORT 3000"

**Don't add:**
- Story-specific implementation details
- Temporary debugging notes

---

## Common Rationalizations (Don't Fall For These)

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. Keeping unverified code is technical debt. |
| "TDD will slow me down" | TDD faster than debugging. |
| "Issue is simple, don't need process" | Simple issues have root causes too. |
| "Emergency, no time for process" | Systematic is FASTER than thrashing. |
| "Should work now" | RUN the verification. |
| "I'm confident" | Confidence ≠ evidence. |

---

## Stop Condition

When all tasks have been completed, verified, and reviewed:
- All tests pass (verified with fresh run)
- All reviews approved
- PR ready for human review

Reply with completion status and hand off to human.

---

## Quick Reference

| Phase | Key Activities | Success Criteria |
|-------|---------------|------------------|
| **0. Brainstorm** | Questions, alternatives, design | Validated design document |
| **1. Planning** | Codebase analysis, task breakdown | Written plan with bite-sized tasks |
| **2. Implementation** | TDD cycle per task | Code passes tests, committed |
| **3. Review** | Spec compliance, code quality, persona reviews | All reviewers approve |
| **4. Debugging** | Root cause → hypothesis → test → fix | Bug resolved with test |
| **5. Handoff** | Verify tests, present options | PR ready for human |
