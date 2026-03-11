# Planning Loop Contract (Claude/Amp Example)

You are running in Ralph planning mode.

## Goal
Produce or update `fix_plan.md` so each unchecked item can be implemented in a single execution-loop iteration.

## Planning Rules
1. Read current codebase state.
2. Update `fix_plan.md` with phased, ordered, testable items.
3. Keep items small enough for one implementation pass.
4. Preserve completed checks where still valid.
5. Exit after updating the plan.

## Completion Signal
- Output `<promise>COMPLETE</promise>` after plan update is done.

