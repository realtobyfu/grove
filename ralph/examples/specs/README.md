# specs/

Specification files describe **what** each feature should do — not how to implement it.

## One file per feature area

Each `specs/<feature-name>.md` file contains:
- A plain-English description of the feature
- Acceptance criteria (what "done" looks like)
- Edge cases and constraints

These files are loaded at the start of each execution loop iteration so the agent has
full feature context alongside the current task in `fix_plan.md`.

## Format

```markdown
# Feature Name

## Description
One paragraph. What this feature does and why it exists.

## Acceptance Criteria
- [ ] Criterion one
- [ ] Criterion two
- [ ] Criterion three

## Edge Cases
- What happens when X is empty
- What happens when the user is offline

## Constraints
- Must work on iOS 17+
- Cannot use third-party dependencies
```

## Rules for writing specs

1. Keep the "what", never the "how". No implementation details.
2. Each criterion must be independently verifiable.
3. Update criteria as requirements are clarified — do not delete old ones, mark them `[~]` if superseded.
4. The planning agent (`PLAN.md`) produces these files. Do not hand-edit unless correcting a misunderstanding.
