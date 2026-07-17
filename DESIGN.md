# Grove — Product + UX Spec (July 2026)

## Why this update exists

This replaces the Feb 2026 alignment spec (US-001..US-014, all shipped or superseded).
The July 2026 cycle refocused Grove on its core loop — **save → read → highlight → reflect → link** —
cut ambient AI that wasn't earning its keep, and added newsletters. This doc records the
current product contract and the principles behind it.

## Product principles

1. **The core loop comes first.** Capture, reading, highlighting, and linking must be excellent
   before any proactive AI earns screen space.
2. **AI at moments of user intent, not ambient.** Dialectics chat, board suggestions at capture,
   and on-device ranking are the right shapes. Silent LLM writes (auto-connect, auto-overview)
   are not — they were removed.
3. **Nothing silent, nothing dead.** Every engine must have a visible surface; every setting must
   describe real behavior. Dead code gets deleted, not parked.
4. **Monochrome, quiet, typographic.** Hierarchy through weight/size/contrast. The reader is the
   flagship of the design system, not an embedded website.
5. **No schema changes for convenience.** Small state → `item.metadata`; large content → disk
   caches. CloudKit sync stays untouched.

## Current experience contract

### Capture
- Capture bar (Home), ⌘N overlay, ⌘⇧K Quick Capture window, and menu bar extra all accept
  **links and plain-text notes** and route through `CaptureService.captureItemDetailed`.
- Duplicate URLs are detected (normalized: no fragments/utm/trailing slash) → "Already in your
  library" flash instead of a second item.
- Post-capture pipeline is metadata fetch + **suggested** tags only (confirm/dismiss chips in
  triage). No LLM overview, no silent auto-connect.

### Reading (the flagship)
- Articles extract via bundled Readability.js on first load, cached to disk
  (`Application Support/GroveReaderCache/`), and open in **Reader mode**: Grove typography
  (embedded Newsreader/IBM Plex), light/dark, offline-capable.
- Typography controls: 4 font sizes, narrow/wide measure, serif/sans. Persisted.
- Read-time estimate in the header; scroll position persists (`metadata["readingProgress"]`)
  and restores.
- Reader ⇄ Original toggle; extraction failure (paywall/SPA) silently stays on the live page.

### Highlighting
- Selecting text in either web mode (or native note content on macOS) shows a floating pill:
  **Highlight** / **Highlight & Reflect**.
- Pure highlights are valid ReflectionBlocks (empty prose + non-empty `highlight` is never
  auto-deleted). Highlight & Reflect opens the editor with the quote attached.
- Tapping a highlight quote in the reflections panel jumps to the passage in the source
  (`scrollToText`, both modes).

### Links & backlinks
- `[[Wiki-links]]` create `.related` Connections at **every** save point via `WikiLinkSync`
  (Write panel, in-reader edits, reflections, chat-created reflections/notes, synthesis,
  nudge-bar reflections, iOS editor) — typed links count, not just autocomplete.
- The Inspector shows outgoing Connections and a clickable **Backlinks** section.
- Wiki-links are tappable everywhere markdown renders, including synthesis previews.
- The graph view was **removed** — backlinks + boards + tags are the navigation contract;
  Connection data is unchanged.

### Library & inbox
- Library: sort menu (recently updated / date added / title), Archived filter chip,
  Archive/Unarchive on rows, bulk Move/Archive/Delete, debounced search (excludes archived).
- Inbox triage on Home: keyboard j/k/1/2/3, tag chips, board auto-assign ≥0.78 confidence.
- **Reading queue**: "Queued for later (N)" disclosure expands an ordered queue
  (soonest-return first) with Read now / Return to inbox. 60s auto-restore preserved.

### Newsletters (RSS)
- Curated directory (`grove/Resources/NewsletterCatalog.json`, ~20 verified feeds) with
  Subscribe/✓/dismiss, ranked on-device against the user's tags/titles (keyword + embedding;
  no LLM). Reason lines only on strong tag matches.
- Subscriptions settings pane (both platforms): manage sources, error badges, add-by-URL,
  "Suggested from your library" (auto-discovered feeds arrive **disabled** — subscribe/dismiss).
- Fetch pipeline runs on foreground (`FeedFetchService.refreshIfNeeded`, 4h cadence,
  3/feed + 20/cycle caps, 14-day expiry).
- Inbox shows feed items in a collapsed **"From your subscriptions"** section — personal
  captures stay primary. Per-source "Fewer like this" / Unsubscribe on cards; sources with
  ≥10 dismissals and 0 keeps are throttled to 1/cycle.

### Nudges & resurfacing
- Engine remains slim: **resurface + stale inbox** only. NudgeBarView is mounted on macOS Home
  (act/dismiss/inline-reflect); engagement feeds `ResurfacingService` interval doubling.
- Notifications remain opt-in. Legacy NudgeType cases persist in the model for decode safety
  but are never created.

### Dialectics (unchanged this cycle)
- User-initiated agentic chat over the knowledge base with search/read/write tools;
  save-as-note/reflection/connection; searchable history; wiki-linked outputs.

## Removed this cycle (do not resurrect without a reason)
- Graph visualization view.
- SmartNudgeService, WeeklyDigestService, CheckInTriggerService, ReflectionPromptService,
  SuggestionRankingService (+ HomeSuggestionsSection/SuggestedArticleCard),
  ConnectionSuggestionService (incl. silent auto-connect), ConnectionSuggestionPopover,
  NoteEditorView, LibraryGridView, capture-time LLM overview generation.

## Known gaps / next candidates
- Duplicate-capture to a specific board doesn't attach the existing item to that board.
- Jump-to-highlight on a slow uncached live page can land at top until load completes.
- Reader-mode highlights are text-anchored (first occurrence), not offset-anchored.
- iOS native-note selection can't drive the highlight bar (no selection callback from
  `.textSelection(.enabled)`); article path is covered.
- Starter → chat handoff still opens assistant-voiced (spec'd as user-message in Feb doc;
  deliberately deferred).
- Dialectics has no streaming; tool-loop progress is invisible while it works.
