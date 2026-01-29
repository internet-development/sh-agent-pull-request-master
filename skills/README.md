# Skills

Skills are mandatory workflows that must be invoked for specific task types. They are not suggestions - if a skill applies, you MUST use it.

## Available Skills

| Skill | When to Use |
|-------|-------------|
| [test-driven-development](./test-driven-development.md) | Before writing ANY implementation code |
| [systematic-debugging](./systematic-debugging.md) | When encountering ANY bug or test failure |
| [verification-before-completion](./verification-before-completion.md) | Before claiming ANY work is complete |
| [two-stage-review](./two-stage-review.md) | When reviewing ANY implementation |
| [brainstorming](./brainstorming.md) | Before ANY creative work (features, components) |

## The Rule

**If a skill applies to what you're doing, you MUST use it.**

This is not negotiable. This is not optional. You cannot rationalize your way out of this.

## Common Rationalizations to Avoid

| Thought | Reality |
|---------|---------|
| "This is just a simple fix" | Simple fixes have root causes. Use systematic-debugging. |
| "I know TDD, I'll just do it" | Reading the skill keeps you honest. |
| "I'll verify at the end" | Verify after EACH claim. Use verification-before-completion. |
| "The code looks fine" | Use two-stage-review. Check spec compliance THEN quality. |
| "I know what to build" | Use brainstorming. Validate understanding first. |

## How to Use

1. Before starting a task, check which skills apply
2. Read the skill file completely
3. Follow the skill exactly
4. Don't skip steps
5. Don't rationalize shortcuts

## Adding Skills

New skills should follow the pattern in existing files:
- Clear "use when" trigger
- Iron law or core principle
- Step-by-step process
- Red flags and rationalizations
- Verification checklist

Skills are adapted from [obra/superpowers](https://github.com/obra/superpowers).
