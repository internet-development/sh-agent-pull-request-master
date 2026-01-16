# Workflow: Verify with Scope

This workflow ensures that work stays within defined boundaries and doesn't expand unexpectedly.

## Prerequisites

- [ ] Original task/directive is documented
- [ ] Acceptance criteria are defined
- [ ] Work has been completed (implementation, research, etc.)

## Scope Definition Review

- [ ] What was the original ask?
- [ ] What are the explicit acceptance criteria?
- [ ] What are the explicit non-goals (if documented)?
- [ ] What constraints were given?

## Work Product Inventory

List everything that was produced:

- [ ] Files created
- [ ] Files modified
- [ ] Files deleted
- [ ] Dependencies added/removed
- [ ] Configuration changes
- [ ] Documentation changes

## Scope Alignment Check

For each work product, verify:

- [ ] Is this directly required by an acceptance criterion?
- [ ] If not directly required, is it a necessary prerequisite?
- [ ] If neither, why was this included?

### Red Flags for Scope Creep

- [ ] "While I was there, I also..."
- [ ] Refactoring unrelated code
- [ ] Adding features not in acceptance criteria
- [ ] Fixing bugs not related to the task
- [ ] Updating dependencies beyond what's needed
- [ ] Adding "nice to have" improvements

## Scope Violation Categories

### Hard Violations (Must Revert)
- Changes that introduce new features
- Changes to unrelated systems
- Changes that significantly increase risk

### Soft Violations (Discuss with Director)
- Minor cleanups in touched files
- Obvious bug fixes discovered during work
- Documentation improvements

### Acceptable Expansions
- Required refactoring to implement the feature
- Test infrastructure needed for new tests
- Type updates required by changes

## Verification Questions

For the overall change:

- [ ] Could this PR be smaller and still meet acceptance criteria?
- [ ] Are there changes that could be a separate PR?
- [ ] Would removing any file still leave a valid PR?
- [ ] Is every line change justified by acceptance criteria?

## Scope Adjustment Process

If scope violations are found:

1. **Document**: What is out of scope and why
2. **Decide**: Revert, separate PR, or accept with justification
3. **Communicate**: Inform Director of scope decision
4. **Track**: If deferring work, create follow-up task

## Final Verification

- [ ] All work products map to acceptance criteria
- [ ] No unjustified additions
- [ ] Scope creep (if any) is documented and approved
- [ ] PR is as small as it can be while meeting requirements

## Output

Document scope verification result:

```json
{
  "scope_verified": true|false,
  "in_scope_items": ["..."],
  "out_of_scope_items": [
    {
      "item": "...",
      "reason": "...",
      "decision": "revert|separate_pr|accept",
      "justification": "..."
    }
  ],
  "recommendations": ["..."]
}
```
