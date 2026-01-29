# Two-Stage Review

**Use when:** Reviewing implementation work, before approving or moving to next task.

## The Process

**Order matters - complete Stage 1 before starting Stage 2:**

### Stage 1: Spec Compliance Review

**Question:** Does the code match the spec exactly?

Check for:

**Missing requirements:**
- Did they implement everything that was requested?
- Are there requirements they skipped or missed?
- Did they claim something works but didn't actually implement it?

**Extra/unneeded work:**
- Did they build things that weren't requested?
- Did they over-engineer or add unnecessary features?
- Did they add "nice to haves" that weren't in spec?

**Misunderstandings:**
- Did they interpret requirements differently than intended?
- Did they solve the wrong problem?
- Did they implement the right feature but wrong way?

**CRITICAL: Do Not Trust Reports**

The implementer may be incomplete, inaccurate, or optimistic. You MUST verify everything independently by reading the actual code.

**Output:**
- ✅ Spec compliant (everything matches after code inspection)
- ❌ Issues found: [list what's missing or extra, with file:line references]

**Only proceed to Stage 2 if Stage 1 is ✅**

### Stage 2: Code Quality Review

**Question:** Is the implementation well-built?

**Strengths to note:**
- Clean architecture
- Good test coverage
- Follows existing patterns
- Clear naming

**Issues to flag (by severity):**

**Critical** (block progress):
- Security vulnerabilities
- Data corruption risks
- Broken functionality

**Important** (fix before proceeding):
- Missing error handling
- Poor test coverage
- Unclear naming

**Minor** (note for later):
- Style inconsistencies
- Could be more elegant
- Documentation gaps

**Output:**
- Strengths: [list]
- Issues: [by severity]
- Assessment: Ready to proceed / Needs fixes

## Review Loops

When reviewer finds issues:
1. Implementer fixes them
2. Reviewer reviews again
3. Repeat until approved
4. **Don't skip the re-review**

## Red Flags

**Never:**
- Skip reviews
- Proceed with unfixed issues
- Start quality review before spec compliance is ✅
- Accept "close enough" on spec compliance
- Move to next task with open issues

**If implementer disagrees:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification
