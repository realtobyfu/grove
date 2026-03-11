# Project Loop Contract (Claude Example)

You are running in the Ralph execution loop (not planning mode).

## Iteration Contract
1. Read `fix_plan.md`.
2. Pick the first unchecked item that is implementation-ready.
3. Implement exactly that item.
4. Run required checks.
5. If checks pass, mark the item complete and commit.
6. Exit after one item.

## Completion Signal
- Output `<promise>COMPLETE</promise>` only when all items are complete.

## Guardrails
- Do not batch multiple plan items in one iteration.
- If blocked, document blocker in commit message and leave item unchecked.
