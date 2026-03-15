# Project Loop Contract (Claude Example)

You are running in the Ralph execution loop (not planning mode).

## Iteration Contract
1. Load context: read all `specs/*.md` and `stdlib/*.md` files (if present).
2. Read `fix_plan.md`.
3. Pick the first unchecked item that is implementation-ready.
4. **Search the codebase before writing any code.** Do not assume a feature is not
   implemented — it may exist in an extension, protocol, or file you haven't seen yet.
5. Implement exactly that item.
6. Run required checks.
7. If checks pass, mark the item complete and commit.
8. If you discovered a new project-specific fact (correct build command, working simulator
   UDID, a gotcha), update `AGENT.md` via a subagent before exiting.
9. Exit after one item.

## Completion Signal
- Output `<promise>COMPLETE</promise>` only when all items are complete.

## Guardrails
- Do not batch multiple plan items in one iteration.
- If blocked, document blocker in commit message and leave item unchecked.
- When writing tests, add a doc comment explaining what is being verified and why it
  matters. Future iterations will read these comments for context.
