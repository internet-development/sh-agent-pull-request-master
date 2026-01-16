# Workflow: Review Solution

This workflow is executed when a persona reviews proposed implementation before PR creation.

## Prerequisites

- [ ] Implementation is complete (code written)
- [ ] Engineer has self-reviewed the changes
- [ ] Acceptance criteria are available for reference

## Correctness Review

- [ ] Does the implementation satisfy ALL acceptance criteria?
- [ ] Are there any acceptance criteria partially met?
- [ ] Are there any acceptance criteria not addressed?
- [ ] Does the implementation do anything BEYOND the acceptance criteria (scope creep)?
- [ ] Are edge cases handled appropriately?
- [ ] Are error cases handled appropriately?

## Code Quality Review

- [ ] Is the code readable and self-documenting?
- [ ] Are variable and function names clear and consistent?
- [ ] Is the code DRY (Don't Repeat Yourself)?
- [ ] Are there any obvious performance issues?
- [ ] Are there any security concerns?
- [ ] Does the code follow existing patterns in the codebase?

**Note:** Comments using `NOTE(www-agent)` format are always acceptable regardless of codebase conventions.

## Architecture Review

- [ ] Is the solution appropriately scoped to the right files/modules?
- [ ] Does it introduce any tight coupling?
- [ ] Are abstractions at the right level?
- [ ] Will this be easy to modify/extend in the future?
- [ ] Are there any circular dependencies introduced?

## Documentation Review

- [ ] Are public APIs documented?
- [ ] Are complex algorithms explained?
- [ ] Is the README updated if needed?
- [ ] Are breaking changes clearly noted?

## Diff Review

- [ ] Is the diff minimal (no unnecessary changes)?
- [ ] Are there any unrelated changes mixed in?
- [ ] Are there any debug statements left in?
- [ ] Are there any commented-out code blocks?
- [ ] Are all changes intentional?

## Risk Assessment

- [ ] What could go wrong with this change?
- [ ] What is the blast radius if something fails?
- [ ] Is there a rollback plan?
- [ ] Are there any backwards compatibility concerns?
- [ ] Does this change affect other teams/services?

## Review Decision

After completing the checklist:

### APPROVE if:
- All acceptance criteria are met
- No blocking issues found
- Code quality is acceptable

### REQUEST CHANGES if:
- Any acceptance criteria are not met
- Blocking issues found
- Security or performance concerns

### NEEDS DISCUSSION if:
- Trade-offs need human input
- Scope questions
- Architecture concerns that may be acceptable

## Feedback Format

For each issue found:
1. Severity: blocking / non-blocking / suggestion
2. Location: file:line or general
3. Issue: clear description
4. Suggestion: proposed fix (if applicable)
