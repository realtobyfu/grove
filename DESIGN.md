# Grove — Design Document

## What Grove Is

Grove is a macOS knowledge-management app where you capture ideas, build a personal knowledge base, and think through your material in conversation with an AI agent that has real access to your knowledge graph.

The core differentiator is **Dialectics**: a conversational interface where the AI can search your items, read your reflections, traverse your connections, and now create synthesis notes — all mid-conversation via an agentic tool-calling loop. This is not "notes + ChatGPT." The agent operates *inside* your knowledge base.

## Design Philosophy

**Three beliefs that shape every decision:**

1. **The blank-canvas problem is the #1 UX failure of knowledge apps.** You open the app, you see your stuff, you think "...now what?" Grove solves this by making the home screen a conversation surface — not a dashboard, not a list of nudge banners, not a stats panel. The app greets you with 2-3 contextual prompt bubbles that are one tap away from a full Dialectics session.

2. **Proactivity through invitation, not notification.** Nudges are notifications (the app tells you something). Prompt bubbles are invitations (the app asks you something). One feels like a to-do list. The other feels like a thinking partner who noticed something interesting. Grove uses invitations.

3. **Conversations produce artifacts, not just text.** A Dialectics conversation should leave traces in the knowledge graph — new items, reflections on existing items, connections between items. Chat transcripts that disappear are waste. Every insight should be one tap away from becoming persistent, searchable knowledge.

## Three Modes

The app has three interaction modes. Not twelve views with a sidebar — three actual modes.

### Capture

Fast, minimal input. One text field, one action. The user types, pastes, or drops content. AutoTagService runs silently on save (tags, one-line summary, board suggestion). No reflection prompts, no connection suggestions, no friction. The capture field should feel like Apple Notes speed, not Notion's template picker.

Global keyboard shortcut to invoke from anywhere. Auto-dismiss after save.

**Auto-board suggestion:** When AutoTagService can't confidently assign an item to an existing board, a non-blocking inline suggestion appears post-save: "This doesn't fit your existing boards. Create 'Phenomenology'?" One tap to accept, one tap to dismiss, or it auto-dismisses after 5 seconds. On cold start (zero boards), always suggest. The user should never have to manually create boards from scratch — the system proposes, the user approves.

**Board emergence over time:** When unboarded items cluster (4-5+ items sharing tags), this is surfaced as a home screen prompt bubble: "You have 6 items about continental philosophy floating around. Want to organize them?" Tapping opens a Dialectics conversation where the agent lists the items, suggests a board name, and the user confirms. A `create_board` write tool in KnowledgeBaseTools handles the creation. Boards should feel like *your* structure, even when the system suggests them — never silently auto-created.

### Library

Browse, search, organize. The hero element is a **full-text search bar** — always visible, queries across titles, content, tags, and reflections. This is the #1 retrieval mechanism in every successful knowledge tool and it must be prominent.

Boards are filters, not containers. The library defaults to showing everything reverse-chronologically. Boards narrow the view. Items show title, summary, tags, last-touched date, and a subtle depth indicator.

The Inspector is read-only detail + manual editing. No auto-generated reflection prompts, no auto-generated connection suggestions. Those features now live in Dialectics where they're better: interactive, steerable, contextual. The inspector keeps: full content view, tag editing, manual connection management, and display of existing reflections.

A "Discuss" button on every item bridges Library → Dialectics. One tap to start a conversation anchored to that item.

### Dialectics

The primary AI surface. This is where thinking happens. The home screen *is* Dialectics in its resting state.

**Home screen state:** 2-3 prompt bubbles generated on app launch from recent activity, stale items, and contradictions. Below: compressed recent items, capture button, search. Tap a bubble → full conversation. Tap an item → inspector. Tap capture → quick entry.

**Conversation state:** Full multi-turn Dialectics with the agentic tool-calling loop. The agent can search items, read details, get reflections, get connections, search by tag, get board items, and now create synthesis notes.

**Actionable outputs:** Every assistant message has subtle action buttons:
- "Save as note" → creates a new Item(.note) in the knowledge base
- Wiki-links in responses are tappable → "View item" or "Add reflection"
- When two items are referenced → "Create connection" with type picker

**History:** Past conversations are browsable and searchable. They're knowledge artifacts too.

## Dialectics: Philosophical Approach

The feature is called **Dialectics** — no qualifier. Not "Socratic Dialectics." The word carries enough weight on its own, and the system modulates between modes based on what the user's knowledge base suggests:

- **Socratic** — Probing assumptions, exposing what the user thinks they know but hasn't examined. Used when the user has deep rabbit holes on one topic without questioning the foundations.
- **Hegelian** — Thesis-antithesis-synthesis. Used when the knowledge base contains contradictions (items with `.contradicts` connections) or when the user has collected opposing viewpoints. Naturally maps to the synthesis tool.
- **Nietzschean** — Perspectivism and revaluation. Looking at the same idea from multiple angles, questioning whether the *framework* is right, not just the conclusions. Used when the user has collected perspectives without committing to one.

The LLM reads the shape of the user's knowledge and picks the right approach. This is specified in the system prompt, not in code branching.

## What Was Cut and Why

### LearningPathService + LearningPathView → Removed
Imposed a pedagogical structure (foundational → advanced) on content that isn't a curriculum. The heuristic fallback (sort by depth ascending) revealed the feature's thinness. Users can ask Dialectics "how should I sequence my notes on X?" if they want this.

### Automatic WeeklyDigest generation → Disabled
Auto-creating digest items every week pollutes the knowledge base with meta-content. 52 digest notes per year mixed in with real knowledge. The service is kept in the codebase but not auto-invoked. Users can ask Dialectics "summarize my week."

### Streak, continue-course, connection-prompt nudges → Removed
Streak notifications are a Duolingo pattern. Grove is a contemplative tool, not a habit tracker. Continue-course assumes linear lecture progression. Connection-prompt is replaced by Dialectics' ability to discover connections conversationally. Only spaced-resurfacing and stale-inbox heuristics remain, surfaced as a quiet count in the Library.

### SmartNudgeService + CheckInTriggerService → Replaced by ConversationStarterService
Three separate nudge/trigger services with different scheduling → one service that generates prompt bubbles on app launch. Simpler, more focused, and the output (conversation starters) is higher value than banner notifications.

### ReflectionPromptService UI in Inspector → Removed
Static prompts attached to items are less useful than dynamic conversation that probes, follows up, and adjusts. "Discuss this" (Library → Dialectics) replaces the inspector's reflection prompt section. The service is kept but not auto-invoked.

### ConnectionSuggestionService UI in Inspector → Removed
Same reasoning. LLM-powered connection discovery is better in conversation where the user can accept, reject, or refine. The Jaccard fallback remains available for any future use. Manual connection management stays in the inspector.

## What Was Kept and Why

### AutoTagService
Fast, invisible, genuinely useful. Runs on capture, doesn't interrupt, produces actionable metadata. The user never thinks about it.

### DialecticsService + Agentic Loop
The product's moat. 6 read tools + 1 write tool (create_synthesis), 3-round max, ~50 lines of loop logic. This is what makes Grove different from every other notes app.

### SynthesisService
Synthesis produces a *document* — a new Item with connections to source items. Conversations produce transcripts. Different artifacts with different shelf lives. Kept as a standalone service, also exposed as a Dialectics write tool (`create_synthesis`).

### LLMProvider protocol + GroqProvider
12-line protocol, single implementation. Exponential backoff, token budgets, JSON parsing fallbacks. Clean and production-ready.

### ResurfacingService
Spaced resurfacing is a proven pattern. Kept as a quiet Library indicator, not a push notification.

### Data Model (Item, Board, Tag, Connection, ReflectionBlock, Conversation, ChatMessage)
Sound and unchanged. Typed connections are especially valuable for the agentic loop — the LLM uses connection types to understand relationships.

## Architecture Summary

### Services (post-redesign)

| Service | Role | Invocation |
|---|---|---|
| AutoTagService | Tags, summary, board suggestion on capture | Automatic on save |
| DialecticsService | All conversational AI, agentic tool-calling loop | User-initiated |
| ConversationStarterService | 2-3 prompt bubbles for home screen | App launch, cached |
| SynthesisService | Creates synthesis Item from multiple items | Library multi-select OR Dialectics tool |
| ResurfacingService | Spaced resurfacing candidates | Timer, exposes count to Library |
| WeeklyDigestService | Weekly activity summary | Manual/on-demand only (not auto-invoked) |

### KnowledgeBaseTools (Dialectics)

| Tool | Type | Description |
|---|---|---|
| search_items | Read | Keyword search across titles, content, tags |
| get_item_detail | Read | Full item with content, tags, reflections, depth |
| get_reflections | Read | All reflection blocks for an item |
| get_connections | Read | Incoming + outgoing connections with types |
| search_by_tag | Read | Find all items with a specific tag |
| get_board_items | Read | All items in a named board |
| create_synthesis | Write | Create a synthesis Item from specified items with focus prompt |
| create_board | Write | Create a Board and assign specified items to it |

### Layer Map

```
UI Layer         HomeView, DialecticsView, LibraryView, InspectorView, CaptureView
ViewModels       ItemViewModel, BoardViewModel, InspectorVM, ConversationVM
Services         AutoTag, Dialectics, ConversationStarter, Synthesis, Resurfacing
Core LLM         LLMProvider protocol, GroqProvider, LLMJSONParser, TokenTracker, KnowledgeBaseTools
Data             Item, Board, Tag, Connection, ReflectionBlock, Conversation, ChatMessage, Nudge
```

## UX Principles

- **Search is the #1 retrieval mechanism.** If the user can't find something by typing, no amount of AI will compensate.
- **Capture should take < 3 seconds.** No forms, no templates, no prompts on save.
- **AI features are pull, not push.** The user initiates thinking. The app invites, never interrupts.
- **Every conversation output should be saveable.** Insights that stay trapped in chat transcripts are waste.
- **Fewer features, more depth.** 3 polished modes > 8 half-used services.
- **Organization should be suggested, not required.** Auto-tag silently. Suggest boards when confidence is low. Surface unboarded clusters as invitations. Never force the user to categorize before they save.
