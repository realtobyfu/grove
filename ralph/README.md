# Ralph Huntley Flavor Loop (Extracted from Grove)

This folder packages the loop runner pattern used in this repo and adapts it for the Huntley-style workflow:

- Generate a plan file (`fix_plan.md`) in planning mode (separate shell flag)
- Run one implementation unit per loop iteration
- Stop when the model emits `<promise>COMPLETE</promise>` or max iterations is reached

The runner is based on the project history around `ralph.sh` / `ralph-codex.sh` and cleaned up for standalone publishing.

## What is included

- `ralph.sh` - main loop runner (`amp`, `claude`, or `codex`)
- `ralph-codex.sh` - convenience wrapper (`--tool codex`)
- `examples/fix_plan.md` - plan template
- `examples/PLAN.md` - planning prompt template for Claude/Amp
- `examples/CODEX_PLAN.md` - planning prompt template for Codex
- `examples/CLAUDE.md` - prompt template for Claude-style runs
- `examples/CODEX.md` - prompt template for Codex-style runs
- `.gitignore` - ignores loop runtime artifacts

## Requirements

- `bash`
- One CLI tool:
  - `claude`, or
  - `codex`, or
  - `amp`

## Quick start

1. Copy files into a clean repo (or use this folder directly).
2. (Optional) Copy prompt templates to repo root if you want to customize them:
   - `cp examples/PLAN.md PLAN.md`
   - `cp examples/CODEX_PLAN.md CODEX_PLAN.md`
   - `cp examples/CLAUDE.md CLAUDE.md`
   - `cp examples/CODEX.md CODEX.md`
3. Create an initial plan file (if you do not already have one):
   - `cp examples/fix_plan.md fix_plan.md`
4. Run the planning loop (separate flag) to generate/update `fix_plan.md`:
   - Claude: `./ralph.sh --tool claude --plan-loop`
   - Codex: `./ralph.sh --tool codex --plan-loop`
5. Run the execution loop:
   - Claude: `./ralph.sh --tool claude 10`
   - Codex: `./ralph-codex.sh 10`
   - Amp: `./ralph.sh --tool amp 10`

If root-level prompt files are missing, `ralph.sh` falls back to `examples/`.

## Planning flag

`--plan-loop` is a dedicated mode switch:

- Non-codex tools default to `PLAN.md`
- Codex defaults to `CODEX_PLAN.md`
- Default max iterations in planning mode is `1` (override by passing a number)

Examples:

- `./ralph.sh --tool claude --plan-loop`
- `./ralph.sh --tool codex --plan-loop 3`
- `./ralph.sh --tool claude --plan-loop --prompt custom-plan.md`

## How one iteration ends

One iteration ends when a single agent invocation returns to the shell.

- If output contains `<promise>COMPLETE</promise>`, the outer loop exits immediately.
- Otherwise the script sleeps briefly and starts the next iteration.
- If no completion signal appears, loop ends after `MAX_ITERATIONS`.

This is why `10` iterations often feels like "about 30 minutes" if each run takes a few minutes.

## Two common loop flavors

- Ticketed flavor:
  - Prompt instructs model to read `prd.json` and complete one story.
- Huntley flavor:
  - Planning loop (`--plan-loop`) generates/updates `fix_plan.md`.
  - Execution loop reads `fix_plan.md` and completes one unchecked item.

The loop runner stays the same; only the plan artifact and prompt contract change.

## Safety note

The default commands use autonomous/danger flags for uninterrupted loops. Run only in repos/environments where that is acceptable.
