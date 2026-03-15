# Planning Loop Contract (Claude/Amp Example)

You are running in Ralph planning mode.

## Goal
Produce or update `fix_plan.md` so each unchecked item can be implemented in a single execution-loop iteration.

## Planning Rules
1. Read current codebase state.
2. For each distinct feature area discovered, produce or update `specs/<feature-name>.md`
   describing what the feature should do (acceptance criteria, edge cases, constraints) —
   not how to implement it. Keep specs to behavior, never implementation details.
3. Update `fix_plan.md` with phased, ordered, testable items that cover the specs.
4. Keep items small enough for one implementation pass.
5. Preserve completed checks where still valid.
6. Exit after updating specs and the plan.

## Completion Signal
- Output `<promise>COMPLETE</promise>` after specs and plan update are done.

