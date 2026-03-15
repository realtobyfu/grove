# Plan Regeneration Contract (Claude Example)

You are running in Ralph plan-regeneration mode. The goal is to produce a fresh,
accurate `fix_plan.md` that reflects the current state of the codebase.

## Steps

1. Read all `specs/*.md` files to understand what the project is supposed to do.
2. Read `fix_plan.md` and note which items are already checked `[x]`.
3. Search the codebase for:
   - `TODO`, `FIXME`, `HACK` comments
   - Placeholder or stub implementations (empty bodies, `fatalError`, hardcoded return values)
   - Features described in `specs/*.md` that do not appear to be implemented
4. Cross-reference your findings against the checked items in `fix_plan.md`.
   - If a checked item has a real implementation: keep it checked.
   - If a checked item appears incomplete or was only partially done: uncheck it with a note.
5. Produce a new `fix_plan.md`:
   - Preserve completed `[x]` items (do not delete history).
   - Add newly discovered work as unchecked `[ ]` items in the appropriate phase.
   - Order unchecked items by dependency (foundational work first).
   - Each item must be completable in a single execution-loop iteration.

## Output

Rewrite `fix_plan.md` in place, then output `<promise>COMPLETE</promise>`.

## Guardrails

- Do not implement anything — only audit and update the plan.
- Do not remove `[x]` items unless you have strong evidence the implementation is missing.
- If uncertain whether something is implemented, add it as a `[ ]` item with a note.
