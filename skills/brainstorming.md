# Brainstorming

**Use when:** Before any creative work - creating features, building components, adding functionality, or modifying behavior.

## The Process

### Understanding the Idea

1. **Check current project state first**
   - Files, docs, recent commits
   - Understand what exists before proposing changes

2. **Ask questions one at a time**
   - NOT: "What do you want to build, what color, what size, where should it go?"
   - YES: "What problem are you trying to solve?"
   - Prefer multiple choice when possible

3. **Focus on understanding**
   - Purpose - why is this needed?
   - Constraints - what can't change?
   - Success criteria - how do we know it works?

### Exploring Approaches

1. **Propose 2-3 different approaches**
   - Each with clear trade-offs
   - One should be your recommendation

2. **Present options conversationally**
   - Lead with your recommendation
   - Explain why you recommend it
   - Be clear about trade-offs

### Presenting the Design

Once you believe you understand what you're building:

1. **Break into sections (200-300 words each)**
   - Architecture
   - Components
   - Data flow
   - Error handling
   - Testing

2. **Ask after each section**
   - "Does this look right so far?"
   - Be ready to go back and clarify

3. **Be flexible**
   - Go back when something doesn't make sense
   - Update understanding based on feedback

### After the Design

1. **Document the validated design**
   - Write to `docs/plans/YYYY-MM-DD-<topic>-design.md`
   - Commit the design document

2. **Ask before proceeding**
   - "Ready to set up for implementation?"
   - Don't assume approval means "start coding now"

## Key Principles

| Principle | Why |
|-----------|-----|
| One question at a time | Don't overwhelm |
| Multiple choice preferred | Easier to answer |
| YAGNI ruthlessly | Remove unnecessary features |
| Explore alternatives | Always 2-3 approaches before settling |
| Incremental validation | Present in sections, validate each |
| Be flexible | Go back when something doesn't make sense |

## Red Flags

If you're doing any of these, STOP:
- Jumping straight to code
- Proposing only one approach
- Not asking clarifying questions
- Presenting entire design at once
- Assuming requirements are clear
- Adding features that weren't requested

## Example Flow

```
User: "Add a login system"

Agent: "I'll help you add authentication. Let me understand what you need.

First: What type of users will be logging in?
a) Internal team members only
b) External customers
c) Both
d) Other"

User: "Internal team only"

Agent: "Got it - internal team authentication.

For internal auth, I'd recommend:
1. **OAuth with existing provider** (Google, Okta) - if you already have identity management
2. **Simple username/password** - if you need standalone auth

Option 1 is usually better for internal teams because... [reasons]

Which fits your situation better?"

[continues with one question at a time...]
```
