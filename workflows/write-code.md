# Workflow: Write Code

This workflow is executed by the **Engineer** persona when implementing code changes.

## Prerequisites

- [ ] Acceptance criteria received from Project Manager
- [ ] Task scope is clear and bounded
- [ ] Required research (if any) has been completed
- [ ] Branch naming convention confirmed: `@{GITHUB_USERNAME}/slug-lowercase-title`

## Pre-Implementation Checklist

- [ ] Read and understand the acceptance criteria completely
- [ ] Identify all files that will need modification
- [ ] Check for existing patterns in the codebase to follow
- [ ] Identify potential breaking changes

## Implementation Steps

- [ ] Create feature branch using correct naming convention
- [ ] Make complete, focused changes that address only the acceptance criteria
- [ ] Follow existing code style and conventions from other similar files
- [ ] Aim for a complete, showcase implementation to impress the team

## Code Quality Gates

- [ ] No hardcoded secrets or credentials
- [ ] No console.log statements in production code (use proper logging)
- [ ] All new functions have clear names that describe their purpose
- [ ] Complex logic has inline comments explaining "why" not "what"
- [ ] No unused imports or variables
- [ ] Alphabetize when possible
- [ ] No TODO comments without associated tracking

## Documentation Updates

- [ ] Update inline documentation for public APIs
- [ ] Update type definitions if applicable

## Pre-Commit Verification

- [ ] Build succeeds

## Commit Guidelines

- [ ] Each commit is atomic and self-contained
- [ ] Commit messages follow conventional format
- [ ] Commit messages explain "why" not just "what"
- [ ] No commits with "WIP" or "fixup" in final branch

## Handoff to Review

- [ ] Push branch to remote
- [ ] Request PR creation via Director
- [ ] Provide summary of changes for reviewers
- [ ] Note any areas requiring extra scrutiny
