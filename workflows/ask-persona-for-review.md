# Workflow: Ask Persona for Review

This workflow is executed when one persona needs input or review from another persona.

## Prerequisites

- [ ] Requesting persona has clear, specific questions
- [ ] Context is prepared for the target persona
- [ ] The request is within the target persona's expertise

## Persona Capabilities Reference

### Director
- Coordination and orchestration
- Quality gate enforcement
- Conflict resolution
- Final approval decisions

### Engineer
- Code implementation review
- Technical feasibility assessment
- Architecture decisions
- Performance considerations

### Project Manager
- Acceptance criteria validation
- Scope verification
- Risk assessment
- TODO prioritization

### Researcher
- External information gathering
- API/dependency verification
- Best practice validation
- Documentation lookup

### Technical Writer
- Documentation review
- PR description quality
- Clarity of communication
- Grammar and style

## Request Preparation

- [ ] Identify the right persona for the request
- [ ] Prepare specific, answerable questions
- [ ] Provide necessary context (don't assume knowledge)
- [ ] Define what "done" looks like for this request
- [ ] Set urgency level (blocking / non-blocking)

## Request Format

```json
{
  "from_persona": "Engineer",
  "to_persona": "Researcher",
  "request_type": "review|question|validation|input",
  "urgency": "blocking|non-blocking",
  "context": {
    "task": "Brief description of current task",
    "relevant_files": ["file1.ts", "file2.ts"],
    "current_state": "What has been done so far"
  },
  "questions": [
    "Specific question 1",
    "Specific question 2"
  ],
  "expected_output": "What format/content is expected in response"
}
```

## Request Quality Checklist

- [ ] Questions are specific, not vague
- [ ] Context is sufficient to answer without back-and-forth
- [ ] Request matches persona's expertise
- [ ] Expected output format is clear
- [ ] Urgency is correctly categorized

## Response Handling

When receiving a response:

- [ ] Verify all questions were addressed
- [ ] Clarify any ambiguous responses
- [ ] Acknowledge receipt and integration of feedback
- [ ] Update work based on response
- [ ] Document how response affected decisions

## Escalation Path

If the target persona cannot answer:

1. Persona should clearly state what they cannot answer
2. Persona should suggest who else might help
3. If no persona can help, escalate to Director
4. Director may request human input if needed

## Anti-Patterns to Avoid

- Asking vague questions ("Is this good?")
- Requesting work outside persona's role
- Bypassing the Director for coordination
- Not providing sufficient context
- Making blocking requests for non-blocking needs

## Communication Log

All persona-to-persona requests should be logged:

```json
{
  "timestamp": "ISO-8601",
  "from": "persona_name",
  "to": "persona_name",
  "request_summary": "...",
  "response_summary": "...",
  "status": "pending|completed|escalated"
}
```

## Integration with Memory

- Log significant exchanges in task memory
- Patterns that recur should become workflow improvements
- Frequently needed clarifications indicate persona prompt improvements
