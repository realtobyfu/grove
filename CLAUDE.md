# Grove — Ralph Loop Notes (Updated Feb 2026)

## Purpose
This repo is run with a Ralph-style loop. Each iteration should complete exactly one `prd.json` story.

## Source of truth
- `prd.json` — prioritized stories with `passes` status.
- `DESIGN.md` — current product + UX contract.
- `progress.txt` — append-only learnings across iterations.

## Iteration contract
1. Read `prd.json` and pick the highest-priority story where `passes: false`.
2. Implement only that story (do not bundle extra work).
3. Run quality checks:
   - `tuist test` (required)
   - `tuist build` when the story changes view/layout-heavy code
4. If checks pass:
   - set that story's `passes` to `true`
   - update that story's `notes` with concise implementation details
   - append key learnings to `progress.txt`
   - commit with: `ralph: US-XXX - short title`

## Project-specific guidance
- App module name is `grove` (lowercase) in code/tests.
- Prioritize keyboard-first macOS UX: focus behavior, shortcuts, and predictable navigation.
- Keep Home starter UX decision-light (small number of high-quality prompts).
- Dialectics outputs should remain artifact-friendly (saveable, linkable, searchable).
- Avoid dead settings/UI paths that no longer map to active services.

## Engineering guardrails
- Keep LLM calls async and failure-tolerant.
- Parse structured LLM outputs defensively.
- Do not add force unwraps outside previews/tests.
- Prefer small, reviewable diffs over broad refactors.

## If blocked
- Record the blocker clearly in `progress.txt`.
- Keep the story `passes: false` and add a precise note in `prd.json`.
