# Grove — Product + UX Update Spec (Feb 2026)

## Why this update exists

This spec replaces the previous redesign doc with a reality-checked update based on the current codebase.  
Goal: fold UI/UX feedback directly into feature priorities so the next Ralph loop executes the highest-leverage changes first.

## Current state snapshot (verified in code)

### What is already strong
- **Core IA and flows are real and usable**: Home, Library, Boards, Courses, Graph, Inspector, Chat.
- **Dialectics core is mature**: agentic loop, write tools (`create_board`, `create_synthesis`), save-as-note/reflection/connection actions.
- **Library retrieval is strong**: persistent search with debounce, board filter chips, discuss action from list + inspector.
- **Capture flow is fast**: low-friction entry + board suggestions + auto-connect.
- **Dialectics prompt logic improved**: system prompt now explicitly includes Socratic/Hegelian/Nietzschean mode selection.
- **Build health is better**: `tuist test` currently passes.

### What is materially misaligned
- Home now surfaces up to **5** starter bubbles, not the intended 2-3.
- Home starter handoff can lose ORGANIZE context and uses a display-prompt path that injects assistant text instead of sending a first user turn.
- Wiki-links are visually styled but not truly interactive in `MarkdownTextView`.
- Conversation history is browsable but not searchable.
- Global search overlay still executes synchronous full fetches per keystroke and lacks autofocus.
- Nudge settings/model still expose removed categories (streak, continue-course, connection prompts, smart categories) even though engine only creates resurface + stale inbox.
- Cmd+Shift+K Quick Capture command posts a notification with no receiver.
- Product copy and shortcuts docs drift from actual behavior (Dialectics naming, Home/Inbox label mismatch).
- Accessibility semantics are thin for icon-heavy UI.
- Secondary/tertiary token contrast remains below readable thresholds for common text sizes.
- Graph edge semantics are hard to interpret (no legend/type filters).
- Hidden zero-size buttons are still used for keyboard handling in triage/detail surfaces.

## Opinionated product decisions

1. **Home must be decision-light, not feed-like.**
   - 2-3 contextual starters are enough.
   - More than 3 reduces starter quality and increases cognitive load.

2. **A starter is a user intent, not assistant content.**
   - Tapping a starter should create a user message and preserve any attached context (especially ORGANIZE cluster IDs).
   - Assistant-injected “display prompt” openings are ambiguous and weaken traceability.

3. **Wiki-links are a navigation contract, not styling.**
   - If text looks like `[[Item]]`, it must be tappable everywhere markdown is rendered.

4. **History without search is archive, not memory.**
   - Dialectics history must be filterable by title + content.

5. **Settings must describe reality.**
   - Dead nudge categories must not remain visible as active controls.

6. **Keyboard shortcuts must be scoped.**
   - Hidden button hacks are brittle and conflict-prone in editing contexts.

7. **Readability is non-negotiable.**
   - Tertiary/muted text tokens must meet practical contrast targets in both themes.

8. **Interpretability beats clever visuals in graph surfaces.**
   - Add explicit legend and relationship type toggles.

## Updated experience contract

### 1) Home
- Show exactly one “New Conversation” card and up to 3 contextual starters.
- Preserve structured starter metadata (label + cluster tag + cluster item IDs) through action selection.
- Starter-to-chat handoff creates a real first user message.
- ORGANIZE starter seeds cluster item IDs so the first assistant response can reason over the intended set.

### 2) Dialectics
- Use product language **Dialectics** consistently in visible copy.
- Wiki-links in rendered assistant markdown are directly actionable.
- Conversation history popover includes search and keyboard navigation.
- `create_synthesis` tool output includes a wiki-link to the newly created synthesis item.

### 3) Library + Search
- Keep existing library search architecture (already good) and maintain debounce behavior.
- Improve global search overlay for keyboard-first use:
  - autofocus input on open,
  - debounce with cancellation,
  - avoid synchronous all-entity fetch loops on every keypress,
  - use button semantics for results.

### 4) Capture + emergence
- Keep post-save board suggestion pattern.
- Standardize board suggestion auto-dismiss to **5 seconds** via one shared constant.
- Keep board emergence behavior (ORGANIZE prompt bubbles) but make context handoff reliable.

### 5) Nudges
- Engine remains intentionally slim: resurface + stale inbox only.
- Settings UI/model are reduced to reflect this.
- Weekly digest remains manual-only behavior (not part of active nudge categories).

### 6) Accessibility + visual system
- Add explicit accessibility labels/hints on icon-only controls in high-traffic surfaces.
- Raise low-contrast secondary text pairs to readable thresholds.
- Preserve current overall visual direction while correcting readability debt.

### 7) Graph
- Keep board/tag filters.
- Add relationship legend and type toggles for semantic clarity.

## Implementation order (mirrors `prd.json`)

1. US-001 Home prompt density + fallback
2. US-002 Starter handoff context + user-message semantics
3. US-003 Wiki-link interactivity
4. US-004 Searchable conversation history
5. US-005 Global search overlay focus/perf
6. US-006 Nudge settings/model alignment
7. US-007 Quick Capture command wiring
8. US-008 Naming + shortcut documentation alignment
9. US-009 Accessibility baseline pass
10. US-010 Contrast token correction
11. US-011 Graph legend + relationship filters
12. US-012 Scoped keyboard handling (remove hidden zero-size shortcuts)
13. US-013 `create_synthesis` direct wiki-link output
14. US-014 Board suggestion timeout alignment (5s)

## Out of scope for this cycle

- Major architecture rewrites of storage/model layers.
- New feature families beyond this alignment pass.
- Reintroducing removed nudge strategies.
- Large visual redesign departures from current style language.

## Success definition for this cycle

- Home feels focused and intentional on first open.
- Dialectics outputs are navigable and retrievable (wiki-links + searchable history).
- Settings no longer lie about inactive systems.
- Keyboard-first workflows become predictable.
- Readability and accessibility materially improve without harming speed.
