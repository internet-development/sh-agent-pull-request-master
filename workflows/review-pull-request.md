# Workflow: Review Pull Request

This workflow is executed by each Persona when reviewing an open pull request.

## Prerequisites

- [ ] PR has been created and is open
- [ ] PR description is complete
- [ ] All commits are pushed

## Initial Assessment

- [ ] Read PR title and description completely
- [ ] Understand the stated goal and motivation
- [ ] Review acceptance criteria listed in PR
- [ ] Check PR size (number of files, lines changed)
- [ ] Note any areas flagged for extra attention

## Commit Review

- [ ] Review each commit individually
- [ ] Verify commits are logical and atomic
- [ ] Verify commit messages are clear
- [ ] Check that commit history tells a coherent story
- [ ] No "fixup" or "WIP" commits in final PR

## Code Review (File by File)

For each changed file:

- [ ] Understand the purpose of changes in this file
- [ ] Verify changes align with PR description
- [ ] Check for correctness issues
- [ ] Check for style/convention violations
- [ ] Check for potential bugs or edge cases
- [ ] Check for security issues
- [ ] Check for performance issues

## Documentation Review

- [ ] PR description is accurate and complete
- [ ] Code comments are appropriate

**Note:** Comments using `NOTE(www-agent)` format are always acceptable regardless of codebase conventions.

## Security Checklist

- [ ] No secrets or credentials in code
- [ ] No sensitive data logged
- [ ] Input validation present where needed
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities
- [ ] Dependencies are from trusted sources

## Persona-Specific Reviews

### As Director
- [ ] All personas have been consulted
- [ ] Quality gates are met
- [ ] Risk assessment is complete

### As Engineer
- [ ] Implementation is correct and maintainable
- [ ] Code follows best practices
- [ ] No technical debt introduced without justification

### As Project Manager
- [ ] Acceptance criteria are met
- [ ] Scope is appropriate
- [ ] Risks are documented

### As Researcher
- [ ] Any external dependencies are verified
- [ ] API usage is correct
- [ ] No outdated patterns used

### As Technical Writer
- [ ] PR description is clear and well-written
- [ ] Documentation is accurate
- [ ] No grammatical errors

## Comment Guidelines

When leaving comments:

1. **Be specific**: Reference exact lines
2. **Be constructive**: Suggest fixes, not just problems
3. **Categorize severity**:
   - `blocker:` Must fix before merge
   - `suggestion:` Nice to have but not required
   - `question:` Seeking clarification
   - `nit:` Minor style preference

## Review Decision

### APPROVE
- All checklists pass
- No blocking issues
- Ready to merge (pending Director final approval)

### REQUEST CHANGES
- Blocking issues found
- Changes required before merge

### COMMENT
- Questions or suggestions only
- No blocking issues
- May approve in follow-up

## Post-Review

- [ ] Submit review with clear summary
- [ ] If requesting changes, list all required fixes
- [ ] If approving, confirm what was verified
