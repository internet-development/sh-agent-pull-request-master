# Workflow: Determine Final Review

This workflow determines if the Director should give the final approval on a pull request.

## Prerequisites

- [ ] PR has been created and is open
- [ ] All personas have reviewed the PR
- [ ] All requested changes have been addressed

## Review Status Collection

Collect review status from each persona:

| Persona | Review Status | Blocking Issues | Comments |
|---------|---------------|-----------------|----------|
| Engineer | pending/approved/changes_requested | count | notes |
| Project Manager | pending/approved/changes_requested | count | notes |
| Researcher | pending/approved/changes_requested | count | notes |
| Technical Writer | pending/approved/changes_requested | count | notes |

## Approval Requirements

### All Must Be True for Final Review

- [ ] Engineer has approved (code is correct)
- [ ] Project Manager has approved (requirements met)
- [ ] Researcher has approved or confirmed no research needed
- [ ] Technical Writer has approved (documentation is clear)
- [ ] No unresolved blocking comments

### Automatic Blockers (Cannot Proceed)

- [ ] Any persona has requested changes (not yet resolved)
- [ ] CI checks are failing
- [ ] Merge conflicts exist
- [ ] Required reviews are missing

## Quality Gate Verification

The Director must verify each gate before final approval:

### Gate 1: Acceptance Criteria
- [ ] All acceptance criteria marked as met
- [ ] PM has verified criteria coverage
- [ ] No criteria marked as partially met without justification

### Gate 2: Code Quality
- [ ] Engineer confirms code is production-ready
- [ ] No known technical debt introduced

### Gate 3: Documentation
- [ ] Technical Writer confirms clarity
- [ ] User-facing docs updated if needed
- [ ] PR description is complete

### Gate 4: Risk Assessment
- [ ] Risks have been identified and documented
- [ ] Rollback plan exists if needed
- [ ] No high-risk items without mitigation

### Gate 5: Scope
- [ ] Changes are focused and minimal
- [ ] No scope creep detected
- [ ] PR could not be reasonably smaller

## Decision Matrix

```
IF all personas approved AND all gates pass:
  -> READY FOR FINAL REVIEW

IF any persona has pending review:
  -> NOT READY (wait for reviews)

IF any persona requested changes:
  -> NOT READY (address changes first)

IF CI is failing:
  -> NOT READY (fix CI first)

IF gates fail:
  -> NOT READY (address gate failures)
```

## Final Review Process

When all conditions are met:

1. Director performs final review
2. Director verifies all gates one more time
3. Director leaves approval comment

### Director Approval Format

For testing/development phase:
```
LGTM

All quality gates verified:
- [ ] Acceptance criteria met
- [ ] Code reviewed and approved
- [ ] Risks assessed
- [ ] Scope verified

Ready for human merge.
```

### Important Constraints

- [ ] Director must NOT merge the PR
- [ ] Director must NOT use auto-merge
- [ ] Human will manually verify and merge

## Post-Approval

After Director approves:

1. Notify that PR is ready for human review
2. Summarize what was verified
3. Highlight any areas for human attention
4. Wait for human to merge

## Exceptions

### When to Escalate to Human Before Approval

- Security-sensitive changes
- Breaking changes to public APIs
- Changes to critical infrastructure
- Uncertainty about business requirements
- Conflicting requirements from different personas
