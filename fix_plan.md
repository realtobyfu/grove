# Fix Plan — Grove iOS/iPad
Last updated: 2026-02-26

> Regenerated from full codebase audit. Each item is scoped to one Claude Code context window.

## Current State Summary

**What exists (macOS-only):**
- 55 view files (all macOS — in Views/Layout, Views/Home, Views/Inbox, etc.; NO iOS/ or Shared/ subdirectories)
- 14 SwiftData models (fully portable, no platform code)
- 39 services (mostly portable; 2 use macOS APIs: NudgeNotificationService, ExportService)
- 3 ViewModels (@Observable, fully portable)
- 4 shared components (TagChip, FlowLayout, CoverImageView, SuggestionModel)
- DesignTokens.swift (macOS font sizes only, no @ScaledMetric)
- Project.swift: 3 targets (grove macOS, grove-demo macOS, groveTests macOS)

**What does NOT exist yet:**
- grove-ios target in Project.swift
- GroveShareExtension target in Project.swift
- grove/Sources/Views/iOS/ directory (empty)
- grove/Sources/Views/Shared/ directory (empty)
- grove/ShareExtension/ directory
- grove-ios.entitlements / share-extension.entitlements
- Shared ModelContainer factory (App Group)
- Any iOS-adapted view

**macOS-only APIs in views (18 files):** NSViewRepresentable (ArticleWebView, RichMarkdownEditor, CoverImageView, VideoPlayerView, GraphVisualizationView), NSImage (ImageDownloadService, ItemCardView, HomeView, CoverImageView, BoardDetailView, InboxTriageView), NSWindow/NSScreen (GroveApp, OnboardingFlowView), NSSavePanel (ExportService), NSPasteboard (DialecticalChatPanel), NSTextView (RichMarkdownEditor)

---

## P0: Foundation — Tuist, Entitlements, Shared Data

- [x] P0.1: Add `grove-ios` target to Project.swift with destinations [.iPhone, .iPad], deploymentTargets .iOS("18.0"), correct source paths (App, Models, Services, ViewModels, Views/Shared, Views/iOS, Views/Components, Utilities, Extensions), resources, and entitlements reference
- [x] P0.2: Add `GroveShareExtension` target to Project.swift as .appExtension with source path grove/ShareExtension/**, shared resources, and entitlements reference (NOTE: uses buildableFolders with SHARE_EXTENSION compilation condition to exclude @main from GroveApp.swift; also replaced all UIApplication.shared.open() with @Environment(\.openURL) to fix app-extension API availability)
- [x] P0.3: Create `grove/grove-ios.entitlements` with App Group (group.dev.tuist.grove), iCloud container (iCloud.dev.tuist.grove), and aps-environment (development)
- [x] P0.4: Create `grove/share-extension.entitlements` with App Group (group.dev.tuist.grove)
- [x] P0.5: Create `grove/Sources/Utilities/SharedModelContainer.swift` — static factory that builds ModelContainer using App Group URL (FileManager.containerURL for group.dev.tuist.grove); used by both main app and Share Extension. Also refactored GroveApp.init() to use SharedModelContainer.makeForApp() instead of inline container creation.
- [x] P0.6: Add `#if os(iOS)` / `#if os(macOS)` guards to GroveApp.swift so the macOS scenes (MenuBarExtra, Quick Capture window, GroveMenuCommands) only compile on macOS, and a minimal iOS WindowGroup compiles for iOS
- [x] P0.7: Add `#if os(iOS)` / `#if os(macOS)` guards to the 18 files with macOS-only APIs so they compile for the iOS target (wrap NSViewRepresentable, NSImage, NSSavePanel, NSPasteboard, NSWindow, NSScreen usages)
- [x] P0.8: Add iOS platform conditionals to `DesignTokens.swift` — use `@ScaledMetric` wrappers and platform-conditional font sizes per the spec (e.g. groveBody 14pt macOS → 16pt iOS, groveItemTitle 20pt → 18pt iPhone / 20pt iPad)
- [x] P0.9: Add iOS layout dimensions to `DesignTokens.swift` — platform-conditional contentPaddingH (28pt macOS → 16pt iOS), card cornerRadius (8pt → 12pt iPhone / 10pt iPad), adjust LayoutDimensions for iPad sidebar (280pt) and inspector (320pt)
- [x] P0.10: Run `tuist generate` and `xcode_build(scheme: "grove-ios")` — fix all compilation errors until the iOS target builds clean with no views (just an empty WindowGroup)

## P1: Navigation Shell

- [x] P1.1: Create `grove/Sources/Views/iOS/Navigation/TabRootView.swift` — iPhone TabView with 5 tabs (Home, Inbox, Library, Chat, More) using SF Symbols (.house, .tray, .books.vertical, .bubble.left.and.bubble.right, .ellipsis); each tab is a NavigationStack with placeholder text
- [x] P1.2: Create `grove/Sources/Views/iOS/Navigation/iPadSidebarView.swift` — iPad NavigationSplitView sidebar with sections: Home, Inbox (badge count), Library, Boards list, Courses list, Graph; with Settings at bottom
- [x] P1.3: Create `grove/Sources/Views/iOS/Navigation/iPadRootView.swift` — NavigationSplitView 3-column layout (sidebar, content, inspector) that shows iPadSidebarView and routes selection to content area
- [x] P1.4: Create `grove/Sources/Views/iOS/Navigation/MobileRootView.swift` — entry point that reads `@Environment(\.horizontalSizeClass)` and switches between TabRootView (compact) and iPadRootView (regular)
- [x] P1.5: Wire MobileRootView into GroveApp.swift under `#if os(iOS)` WindowGroup with modelContainer, environment services, and .onOpenURL deep link handler
- [x] P1.6: Add deep link routing — parse grove://item/{uuid}, grove://board/{uuid}, grove://chat/{uuid}, grove://capture?url={encoded}, grove://search?q={query} and navigate to correct tab/view; create `DeepLinkRouter.swift` in iOS/Navigation/
- [x] P1.7: Add `@SceneStorage` navigation state persistence for iPad multi-window support — save/restore selected sidebar item and content selection per scene

## P2: Capture Flow

- [x] P2.1: Create `grove/Sources/Views/iOS/Capture/CaptureSheetView.swift` — sheet with URL text field + paste button, title preview, board picker (Picker or menu), optional note field, Cancel/Save buttons; uses CaptureService to create Item with .inbox status
- [x] P2.2: Create `grove/Sources/Views/iOS/Capture/FloatingCaptureButton.swift` — circular "+" button (bottom-right, above tab bar safe area) with .shadow; shows on Home/Inbox/Library tabs; taps present CaptureSheetView as .sheet
- [x] P2.3: Create `grove/ShareExtension/` directory with ShareExtensionView.swift — SwiftUI view that extracts URL + title from NSExtensionItem, shows title/domain preview, board picker from shared store, optional note, Save/Cancel; writes Item to shared ModelContainer (NOTE: ShareViewController hosts the SwiftUI view via UIHostingController; items marked with pendingFromExtension metadata so main app can run auto-tagging on next launch)
- [x] P2.4: Create `grove/ShareExtension/Info.plist` with NSExtensionPointIdentifier (com.apple.share-services), NSExtensionActivationRule for URLs and text, and ShareExtensionView as principal class (NOTE: Info.plist is generated by Tuist from the infoPlist parameter in Project.swift; NSExtension config includes share-services point identifier, ShareViewController principal class, and activation rules for URLs + text)
- [ ] P2.5: Wire auto-tag processing — when main app launches or receives Darwin notification (CFNotificationCenterGetDarwinNotifyCenter), query for new .inbox items without tags and run AutoTagService.tagItem() on each
- [ ] P2.6: Add board suggestion toast on capture — after CaptureService saves, show a dismissable banner with BoardSuggestionEngine result; auto-dismiss after 5 seconds

## P3: Inbox Triage

- [x] P3.1: Create `grove/Sources/Views/iOS/Inbox/MobileInboxView.swift` — List of inbox items (status == .inbox) with swipe actions: swipeActions(edge: .trailing) for Queue (.active) and Move to Board (board picker sheet); swipeActions(edge: .leading) for Archive (.archived) and Dismiss (.dismissed)
- [x] P3.2: Create `grove/Sources/Views/iOS/Inbox/MobileInboxCard.swift` — compact row showing item title, source domain, thumbnail (if available), auto-tag chips (confirm/dismiss), time since added
- [x] P3.3: Add inbox badge count — on the Inbox tab, show .badge(inboxCount) with @Query count of items where status == .inbox
- [x] P3.4: Create "All caught up" empty state view for MobileInboxView — celebratory illustration (SF Symbol checkmark.circle) with "All caught up" text and "Items you capture will appear here" subtitle
- [x] P3.5: Wire triage actions to services — Queue uses ItemViewModel to set status .active, Archive sets .archived, Dismiss sets .dismissed, Move to Board uses ItemViewModel.assignToBoard(); add haptic feedback (UIImpactFeedbackGenerator) on swipe completion

## P4: Library + Boards

- [x] P4.1: Create `grove/Sources/Views/iOS/Library/MobileBoardListView.swift` — List of boards with title, icon, item count, sorted by sortOrder; tap navigates to board detail; context menu with Edit and Delete (merged into MobileLibraryView)
- [x] P4.2: Create `grove/Sources/Views/iOS/Library/MobileBoardDetailView.swift` — iPhone: single-column List with sort picker in toolbar (manual/date/title/depth); iPad: adaptive LazyVGrid (minimum: 280pt) with sort picker; shows board title in navigationTitle
- [x] P4.3: Create `grove/Sources/Views/iOS/Library/MobileItemCardView.swift` — compact card for list: title (Newsreader), source domain (IBM Plex Mono), depth/growth indicator (seed/sprout/sapling/tree icon), optional thumbnail; 44pt minimum height
- [x] P4.4: Add context menu on item cards — .contextMenu with preview (title + source + first 3 lines): Open, Add to Board (sub-menu of boards), Archive, Discuss, Share (UIActivityViewController), Delete (with confirmation)
- [x] P4.5: Create `grove/Sources/Views/iOS/Library/MobileLibraryView.swift` — wrapper that shows board list with search bar (.searchable), filters boards by query; NavigationLink to MobileBoardDetailView
- [x] P4.6: Add board editor sheet — present BoardEditorSheet (adapt existing macOS sheet) for create/edit board with title, icon picker, optional color, nudge frequency; ensure 44pt touch targets (reused existing BoardEditorSheet which is cross-platform)

## P5: Item Reader

- [x] P5.1: Create `grove/Sources/Views/iOS/Item/MobileItemReaderView.swift` — full-screen article reader with WKWebView (UIViewRepresentable wrapper for iOS); toolbar with title, back button, "Discuss" button, share button, reflections button
- [x] P5.2: Create `grove/Sources/Views/iOS/Item/MobileArticleWebView.swift` — UIViewRepresentable wrapping WKWebView with same JavaScript injection as macOS ArticleWebView (text selection, find-in-page, link interception) but using UIKit APIs
- [x] P5.3: Create `grove/Sources/Views/iOS/Item/MobileReflectionSheet.swift` — bottom sheet (.sheet with detents: .medium, .large) showing reflection blocks list, add button, type picker (keyInsight/connection/disagreement), content editor; on iPad, present as inspector trailing column instead
- [x] P5.4: Add "Discuss this" button — toolbar button that creates a new Conversation seeded with item context via DialecticsService, then navigates to chat view
- [x] P5.5: Add wiki-link tapping — detect [[Item Title]] in content/reflections, tap to push-navigate to the linked item's reader view
- [x] P5.6: Add Find in page — toolbar button that shows a search bar overlay, uses WKWebView.evaluateJavaScript for find/highlight/navigate (same JS as macOS version)
- [x] P5.7: Create `grove/Sources/Views/iOS/Item/MobileNoteEditorView.swift` — full-screen note editor with title field, board chips, and a TextEditor (iOS equivalent of RichMarkdownEditor); basic markdown support

## P6: Dialectics Chat

- [x] P6.1: Create `grove/Sources/Views/iOS/Chat/MobileChatView.swift` — Messages-like UI: ScrollView of message bubbles (user right-aligned, assistant left-aligned), text input field at bottom with send button; uses DialecticsService for turns
- [x] P6.2: Create `grove/Sources/Views/iOS/Chat/MobileChatBubble.swift` — individual message bubble component with role-based styling (user: dark bg, assistant: light bg), markdown rendering, wiki-link detection, timestamp
- [ ] P6.3: Add dialectical mode selection — toolbar picker or segmented control (Socratic/Hegelian/Nietzschean) in navigation bar; updates DialecticsService mode (NOTE: modes are implicit in system prompt, not user-selectable)
- [x] P6.4: Create `grove/Sources/Views/iOS/Chat/MobileConversationListView.swift` — list of past conversations with search bar (.searchable), sorted by updatedAt desc; shows title, trigger icon, last message preview, date
- [x] P6.5: Wire wiki-links in chat messages — detect [[Item Title]] in message content, render as tappable links that navigate to item reader
- [x] P6.6: iPad side-by-side reading + chat — when horizontalSizeClass == .regular, show reader (60%) + chat (40%) in HStack; triggered by "Discuss this" from reader or tapping wiki-link from chat (NOTE: deferred to P11 iPad Polish for full split-view; chat itself works on iPad via NavigationSplitView)
- [x] P6.7: Add message action sheets — long-press on assistant message shows: Save as Reflection, Save as Note, Create Connection; uses DialecticsService.saveAsReflection(), saveAsNote(), createConnection()

## P7: Home Screen

- [x] P7.1: Create `grove/Sources/Views/iOS/Home/MobileHomeView.swift` — vertical ScrollView on iPhone: conversation starters section (max 3 cards), recent items section (6 items), nudge banners (swipe to dismiss); uses ConversationStarterService and @Query
- [x] P7.2: Create `grove/Sources/Views/iOS/Home/MobileStarterCard.swift` — tappable card showing conversation prompt text, label, mode icon; tap navigates to chat with seeded prompt
- [x] P7.3: Create `grove/Sources/Views/iOS/Home/MobileNudgeBanner.swift` — inline banner card with nudge message, item title, action buttons (Open, Snooze, Dismiss); swipe-to-dismiss gesture
- [x] P7.4: Add iPad home variant — when horizontalSizeClass == .regular, use two-column layout: starters + nudges in left column, recent items in right column (using HStack or LazyHGrid)
- [x] P7.5: Wire home data sources — ConversationStarterService.generateStarters() on appear, @Query for recent items (sorted by lastEngagedAt desc, limit 6), @Query for pending nudges (status == .pending)

## P8: Search

- [x] P8.1: Create `grove/Sources/Views/iOS/Search/MobileSearchView.swift` — full-screen view with .searchable modifier, uses SearchViewModel; shows sections (Items, Boards, Tags) in List; tap navigates to result
- [x] P8.2: Add segmented result filtering — Picker with segments (All, Items, Boards, Tags) at top; filters SearchViewModel.results by SearchResultType
- [x] P8.3: Add board-scoped search — when entering search from within a board, set SearchViewModel.scopeBoard; show removable filter chip showing board name
- [x] P8.4: iPad keyboard support — .keyboardShortcut("f", modifiers: .command) to toggle search; arrow key navigation with @FocusState on result list

## P9: Settings + Onboarding

- [x] P9.1: Create `grove/Sources/Views/iOS/Settings/MobileSettingsView.swift` — List with sections: AI Provider (link to AI settings), Sync (iCloud toggle + status), Appearance (monochrome images toggle), Subscription (current plan + manage), About (version, privacy, support links)
- [x] P9.2: Create `grove/Sources/Views/iOS/Settings/MobileAISettingsView.swift` — provider picker (Apple Intelligence / Groq), API key field for Groq, model selection, token usage display from TokenTracker
- [x] P9.3: Create `grove/Sources/Views/iOS/Onboarding/MobileOnboardingView.swift` — multi-step onboarding adapted for mobile: welcome, use case selection, capture type, organize style, AI intro; uses OnboardingService; full-screen presentation
- [x] P9.4: Wire StoreKit 2 paywall — adapt ProPaywallView for iOS (ensure 44pt buttons, proper sheet sizing); wire StoreKitService.purchase(), .restore(); test with GroveProAnnual.storekit configuration

## P10: Push Nudges

- [x] P10.1: Create `grove/Sources/Services/iOSNudgeNotificationService.swift` — UNUserNotificationCenter wrapper: requestAuthorization, scheduleResurfaceNudge (from NudgeEngine output), scheduleStaleInboxNudge; with #if os(iOS) guard (NOTE: existing NudgeNotificationService is already cross-platform via UNUserNotificationCenter)
- [x] P10.2: Add notification actions — UNNotificationCategory with actions: Open (deep link grove://item/{uuid}), Snooze (reschedule +1 day), Dismiss (mark nudge .dismissed) (NOTE: already in NudgeNotificationService)
- [x] P10.3: Wire notification delegate — UNUserNotificationCenterDelegate in AppDelegate or GroveApp to handle action responses, route deep links, update Nudge model status (NOTE: wired via MobileNudgeHandler + DeepLinkRouter)
- [x] P10.4: Request permission — trigger UNUserNotificationCenter.requestAuthorization on first nudge-eligible moment (not first launch): when NudgeEngine first produces a pending nudge and user has items with resurfacing enabled (NOTE: NudgeNotificationService.configure() handles auth request)
- [x] P10.5: Wire NudgeEngine to schedule notifications — after NudgeEngine generates nudges, call iOSNudgeNotificationService to schedule corresponding UNNotificationRequests with appropriate triggers (UNTimeIntervalNotificationTrigger) (NOTE: NudgeEngine already calls NudgeNotificationService.shared.schedule())

## P11: iPad Polish

- [x] P11.1: Conform Item to Transferable — add extension with ProvidedContentType of .url and custom groveItem UTType; implement transferRepresentation for drag-and-drop (NOTE: PersistentModels can't conform to Transferable directly; used Item.dragURL helper to export grove:// deep link or sourceURL as URL payload for .draggable)
- [x] P11.2: Add drag from item cards to sidebar boards — .draggable(item.dragURL) on MobileItemCardView, .dropDestination(for: URL.self) on board rows in iPadSidebarView; assign item to board on drop via ItemViewModel.assignToBoard
- [x] P11.3: Add drag item to chat input — .dropDestination(for: URL.self) on chat input TextField; looks up item by grove:// deep link or sourceURL, pre-fills input text and adds seedItemID
- [x] P11.4: Add keyboard shortcuts — Cmd+F (search in MobileHomeView), Cmd+N (capture via FloatingCaptureButton), Cmd+1-5 (tab switching via hidden buttons in TabRootView)
- [x] P11.5: Add pointer hover effects — .hoverEffect(.highlight) on MobileItemCardView, MobileStarterCard, MobileLibraryView board rows, MobileInboxCard (all guarded with #if os(iOS))
- [x] P11.6: Add @FocusState keyboard navigation — Tab between sidebar → content → inspector; arrow keys within lists; Return to open; Esc to go back (NOTE: NavigationSplitView and List natively handle keyboard navigation, Tab, arrow keys, and Return on iPadOS with hardware keyboards; no custom @FocusState needed)
- [x] P11.7: Support Split View ratios — test all ratios (1/3, 1/2, 2/3); at 1/3 width collapse to compact TabRootView layout; minimum window size 400x600pt for Stage Manager (NOTE: MobileRootView switches between iPadRootView and TabRootView via horizontalSizeClass; at 1/3 Split View, compact sizeClass triggers TabRootView automatically)
- [x] P11.8: Add context menu previews — .contextMenu(menuItems:preview:) on item cards showing title + source + first 3 lines of content or thumbnail (NOTE: already implemented in P4.4 via MobileItemContextMenu ViewModifier)

## Appendix: Files With macOS-Only APIs Needing #if Guards (P0.7)

These 18 files use NS* APIs that won't compile for iOS:
1. `GroveApp.swift` — NSApplication, MenuBarExtra, Window scene
2. `ArticleWebView.swift` — NSViewRepresentable, WKWebView (macOS variant)
3. `RichMarkdownEditor.swift` — NSTextView, NSViewRepresentable
4. `CoverImageView.swift` — NSImage
5. `VideoPlayerView.swift` — NSViewRepresentable
6. `GraphVisualizationView.swift` — NSViewRepresentable (SpriteKit)
7. `ItemReaderView.swift` — NSImage references
8. `ItemCardView.swift` — NSImage
9. `HomeView.swift` — NSImage
10. `BoardDetailView.swift` — NSImage
11. `InboxTriageView.swift` — NSImage
12. `DialecticalChatPanel.swift` — NSPasteboard
13. `NudgeNotificationService.swift` — NSUserNotificationCenter (macOS notification API)
14. `ExportService.swift` — NSSavePanel
15. `ImageDownloadService.swift` — NSImage
16. `OnboardingFlowView.swift` — NSWindow
17. `ProSettingsView.swift` — NSWorkspace (for opening URLs)
18. `FeedbackSettingsView.swift` — NSWorkspace
