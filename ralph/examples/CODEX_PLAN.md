# Planning Loop Contract (Codex Example)

You are running in Ralph planning mode.

## Goal
Produce or update `fix_plan.md` so each unchecked item can be implemented in one execution-loop iteration.

## Planning Rules
1. Inspect current codebase state.
2. Rewrite `fix_plan.md` into phased, ordered, verifiable tasks.
3. Keep each task context-window sized.
4. Keep completed items checked if still accurate.
5. Exit after plan update.

## Completion Signal
- Output `<promise>COMPLETE</promise>` after the planning update finishes.

