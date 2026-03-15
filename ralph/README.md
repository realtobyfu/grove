# Ralph

Autonomous AI agent loop runner for iOS and macOS Swift development.

## Attribution

Ralph was created by [Geoffrey Huntley](https://ghuntley.com/ralph/) and originally published at [github.com/snarktank/ralph](https://github.com/snarktank/ralph). This fork extends the original with an iOS/macOS-specific feedback loop: the agent builds with `xcodebuild`, runs your test scheme, and iterates until the build is green — all without human intervention. If you find this useful, go read Geoffrey's writing first.

## What Ralph Does

Ralph runs a bash loop where each iteration invokes an AI CLI tool with a prompt contract. The agent reads your plan file, implements one task, verifies the result with Xcode, marks the task done, and commits. When all tasks are complete the agent emits a completion signal and the loop exits.

```
ralph.sh (loop)
  └─ iteration N
       ├─ read fix_plan.md
       ├─ implement next [ ] item
       ├─ xcode_build / xcode_test
       ├─ mark [x] done, git commit
       └─ if all done → <promise>COMPLETE</promise> → exit
```

Each iteration is one full AI invocation. Budget 2–5 minutes per iteration when Xcode builds are involved. Ten iterations ≈ 20–50 minutes of unattended work.

## Requirements

- macOS + bash
- Xcode with at least one configured scheme and a simulator destination
- One AI CLI tool: `claude`, `amp`, or `codex`
- Optional: [Tuist](https://tuist.io/) (only if your project uses it for project generation)

## File Structure

| File | Purpose |
|---|---|
| `ralph.sh` | Main loop runner |
| `ralph-codex.sh` | Codex convenience wrapper |
| `examples/CLAUDE.md` | Claude execution loop contract |
| `examples/PLAN.md` | Claude/Amp planning contract |
| `examples/REGEN_PLAN.md` | Mid-project plan regeneration contract |
| `examples/AGENT.md` | Agent self-updating learnings file |
| `examples/fix_plan.md` | Plan template (P0/P1/P2 sections) |
| `examples/specs/` | Feature specification files (one per feature area) |
| `examples/stdlib/` | iOS coding convention reference files |
| `examples/CODEX.md` | Codex execution contract |
| `examples/CODEX_PLAN.md` | Codex planning contract |

## Quick Start (iOS/macOS)

1. Copy the prompt files to your project root, or rely on the `examples/` fallback:
   ```bash
   cp ralph/examples/CLAUDE.md ./CLAUDE.md
   cp ralph/examples/PLAN.md ./PLAN.md
   cp ralph/examples/fix_plan.md ./fix_plan.md
   ```

2. Edit `CLAUDE.md` — set your Xcode scheme and simulator destination in the verification step:
   ```
   xcode_build(scheme: "MyApp", destination: "platform=iOS Simulator,name=iPhone 16")
   ```

3. Run the planning loop to generate `fix_plan.md`:
   ```bash
   ./ralph.sh --tool claude --plan-loop
   ```

4. Review `fix_plan.md`. Keep each task small enough to fit in one context window — if a task feels large, split it.

5. Run the execution loop:
   ```bash
   ./ralph.sh --tool claude 10
   ```

6. **Tuist users:** Add a `tuist generate --no-open` step in `CLAUDE.md` so the agent regenerates the Xcode project after any `Project.swift` changes before building.

## Loop Mechanics

- **Iterations** — each iteration is one complete agent invocation. The loop counts them and stops at `MAX_ITERATIONS`.
- **Completion signal** — when the agent outputs `<promise>COMPLETE</promise>`, the loop exits immediately regardless of remaining iterations.
- **Sleep** — 2 seconds between iterations by default (override with `--sleep N`).
- **Prompt fallback** — if a root-level prompt file is missing, `ralph.sh` looks in `examples/` automatically.

## Customizing CLAUDE.md

The execution prompt contract tells the agent exactly what to do each iteration. A minimal iOS/macOS version looks like this:

```markdown
You are an autonomous iOS/macOS Swift developer.

Each iteration:
1. Read fix_plan.md. Find the first unchecked [ ] item.
2. Implement ONLY that one item. Do not start the next item.
3. Verify: run xcode_build(scheme: "MyApp", destination: "platform=iOS Simulator,name=iPhone 16").
   - If build fails, fix it before proceeding.
   - If tests exist for this change, run xcode_test(scheme: "MyAppTests").
4. Mark the item [x] done in fix_plan.md.
5. git add -A && git commit -m "brief description of change"
6. If all items are done, output <promise>COMPLETE</promise> and stop.
7. If blocked (missing context, ambiguous spec), leave the item unchecked,
   add a note explaining the blocker, and output <promise>COMPLETE</promise>.

TUIST PROJECTS: Run `tuist generate --no-open` before building if Project.swift was modified.
```

Key rules:
- **One item per iteration.** Doing more risks a half-finished state if the build fails.
- **Always verify.** Build errors left uncommitted break the next iteration.
- **Blocker protocol.** The agent should never guess at ambiguous requirements — it should stop and note why.

## Claude Code Skills

Skills add domain-specific knowledge to the agent's context. Reference them in your `CLAUDE.md` with a `@` include or by pasting the skill content directly.

| Skill | When to use |
|---|---|
| `/swiftui-expert-skill` | SwiftUI layout, state management, iOS 26 Liquid Glass adoption |
| `/swift-concurrency` | async/await, actors, Swift 6 migration, data race fixes |
| `/xclaude-plugin:xcode-workflows` | Build system, scheme config, xcodebuild error interpretation |
| `/xclaude-plugin:ui-automation-workflows` | `idb_describe`, `idb_tap`, accessibility tree validation |
| `/xclaude-plugin:crash-debugging` | Crash log analysis, symbolication, stack trace root cause |

Example reference inside `CLAUDE.md`:

```markdown
## Skills in use
- SwiftUI: follow /swiftui-expert-skill patterns for state and view composition
- Concurrency: follow /swift-concurrency patterns; target Swift 6 strict concurrency
- Build: use xclaude xcode_build MCP tool; see /xclaude-plugin:xcode-workflows
```

## Two Workflow Flavors

**Huntley flavor** (default and recommended):
- `--plan-loop` runs first and produces `fix_plan.md` with P0/P1/P2 task sections.
- Execution loop reads `fix_plan.md` one item at a time.
- Natural checkpoints: review the plan before running execution.

**Ticketed flavor:**
- Replace `fix_plan.md` with a `prd.json` or any artifact from your issue tracker.
- Adjust the prompt contract to read from that artifact instead.
- The loop runner itself is unchanged.

## CLI Reference

| Flag | Default | Description |
|---|---|---|
| `--tool claude\|amp\|codex` | `claude` | AI tool to invoke |
| `--plan-loop` | off | Planning mode (reads PLAN.md or CODEX_PLAN.md) |
| `--regen-plan` | off | Mid-project plan refresh (reads REGEN_PLAN.md) |
| `--prompt FILE` | auto | Override the prompt file |
| `--sleep N` | `2` | Seconds to sleep between iterations |
| `N` (positional) | `10` | Max iterations |

Examples:

```bash
# Generate plan
./ralph.sh --tool claude --plan-loop

# Run 15 iterations with amp
./ralph.sh --tool amp 15

# Refresh plan mid-project
./ralph.sh --tool claude --regen-plan

# Custom prompt, slow sleep for expensive builds
./ralph.sh --tool claude --prompt my-prompt.md --sleep 10 5

# Codex shorthand
./ralph-codex.sh 10
```

## Mid-project Plan Refresh

After several execution loops, `fix_plan.md` can drift from reality: some checked items may be incomplete, new TODOs appear in the code, and the original plan may not cover new discoveries from `specs/`.

Run `--regen-plan` to audit and rebuild the plan:

```bash
./ralph.sh --tool claude --regen-plan
```

The `REGEN_PLAN.md` contract tells the agent to:
1. Read all `specs/*.md` to understand intended behavior
2. Search the codebase for `TODO`, `FIXME`, stubs, and placeholder implementations
3. Cross-reference findings against already-checked items in `fix_plan.md`
4. Produce a fresh plan that preserves history but adds newly discovered work

Use this when: you've completed a phase and want to find what was missed, you've added new specs mid-project, or the plan feels stale relative to the codebase.

## Safety Note

Ralph passes autonomy/danger flags to the underlying tools:

- `claude` — `--dangerously-skip-permissions`
- `amp` — `--dangerously-allow-all`
- `codex` — `--full-auto`

Before running an execution loop:

- **Use a dedicated feature branch.** Never run Ralph on `main` with uncommitted changes.
- **Start with a clean working tree.** Partial state is hard to recover from.
- **Keep secrets out of the environment.** The agent sees your shell environment.
- **Wire up a test scheme.** Running tests each iteration dramatically reduces the blast radius of a bad iteration.

## Contributing / License

MIT. Upstream: [github.com/snarktank/ralph](https://github.com/snarktank/ralph). PRs welcome for iOS/macOS workflow improvements — build tooling, Xcode integration, simulator management. General-purpose loop changes belong upstream.
