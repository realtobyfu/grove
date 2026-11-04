import SQLiteData
import SwiftUI

/// iOS Home screen — inbox triage, discussion suggestions, recent items, and nudge banners.
struct MobileHomeView: View {
    private static let maxDiscussionCards = 3

    @Dependency(\.defaultDatabase) private var database
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Fetch(Library.Request()) private var library = Library()
    @FetchAll(Board.order(by: \.sortOrder)) private var boards
    // Animated here because a banner leaves when this next arrives, after any
    // `withAnimation` around the write that dismissed it has ended.
    @FetchAll(Nudge.order { $0.createdAt.desc() }, animation: .default) private var allNudges

    @Environment(ConversationStarterService.self) private var starterService
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @State private var showSearch = false
    @State private var showBoardPicker = false
    @State private var itemToAssign: ItemGraph?
    @State private var selectedSuggestion: PromptBubble?
    @State private var paywallPresentation: PaywallPresentation?

    var onOpenItem: ((ItemGraph) -> Void)? = nil
    var selectedItem: Binding<ItemGraph?>? = nil
    var openedItem: Binding<ItemGraph?>? = nil

    /// Most recently engaged first, and never-engaged last.
    private var allItems: [ItemGraph] {
        library.items.sorted { ($0.lastEngagedAt ?? .distantPast) > ($1.lastEngagedAt ?? .distantPast) }
    }

    /// Newest first.
    private var inboxItems: [ItemGraph] {
        library.items
            .filter { $0.status == .inbox && !$0.isFeedSuggestion }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var pendingNudges: [Nudge] {
        allNudges.filter { $0.status == .pending || $0.status == .shown }
    }

    private var discussionBubbles: [PromptBubble] {
        let dynamicSlotCount = max(0, Self.maxDiscussionCards - 1)
        return Array(starterService.bubbles.prefix(dynamicSlotCount))
    }

    private var newConversationBubble: PromptBubble {
        PromptBubble(
            prompt: "New Conversation",
            label: "CHAT"
        )
    }

    var body: some View {
        List {
            Section {
                InlineCaptureBar()
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)

            Section {
                LearningInvitationView()
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)

            inboxSection
            discussionSuggestionsSection
            nudgesSection
        }
        .listStyle(.plain)
        // A triaged row leaves when `library` next arrives, after any `withAnimation`
        // around the write has ended, so the animation lives here.
        .animation(.default, value: inboxItems.map(\.id))
        .navigationTitle("Today")
        .navigationDestination(for: MobileItemRoute.self) { route in
            MobileItemRouteDestinationView(route: route)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        .sheet(isPresented: $showSearch) {
            MobileSearchView()
        }
        .sheet(isPresented: $showBoardPicker) {
            boardPickerSheet
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
        .sheet(item: $selectedSuggestion) { suggestion in
            MobilePromptActionSheet(
                contextTitle: "Home",
                suggestion: suggestion,
                onOpenDialectics: {
                    startConversation(with: suggestion)
                },
                onStartWriting: {
                    startWriting(with: suggestion.prompt)
                }
            )
        }
        .task {
            await starterService.refresh(items: allItems)
        }
        .keepingCurrent($itemToAssign, in: library)
        .onChange(of: library.items.count) { _, newCount in
            guard newCount > 0, starterService.bubbles.isEmpty else { return }
            Task {
                await starterService.forceRefresh(items: allItems)
            }
        }
    }

    // MARK: - Inbox section

    @ViewBuilder
    private var inboxSection: some View {
        if !inboxItems.isEmpty {
            Section {
                ForEach(inboxItems) { item in
                    openItemRow(item: item) {
                        MobileInboxCard(
                            item: item,
                            onConfirmTag: { tag in confirmTag(tag) },
                            onDismissTag: { tag in dismissTag(tag, from: item) }
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            keepItem(item)
                        } label: {
                            Label("Keep", systemImage: "checkmark.circle")
                        }
                        .tint(Color.textPrimary)

                        Button {
                            itemToAssign = item
                            showBoardPicker = true
                        } label: {
                            Label("Board", systemImage: "folder")
                        }
                        .tint(Color.textSecondary)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            dismissItem(item)
                        } label: {
                            Label("Drop", systemImage: "xmark")
                        }
                    }
                }
            } header: {
                Text("Inbox")
                    .sectionHeaderStyle()
            }
        }
    }

    // MARK: - Discussion suggestions

    @ViewBuilder
    private var discussionSuggestionsSection: some View {
        Section {
            if let bubble = discussionBubbles.first {
                MobileStarterCard(
                    bubble: bubble,
                    showsDisclosureIndicator: horizontalSizeClass == .regular
                ) {
                    if horizontalSizeClass == .regular {
                        selectedSuggestion = bubble
                    } else {
                        startConversation(with: bubble)
                    }
                }
            } else {
                MobileStarterCard(bubble: newConversationBubble) {
                    startNewConversation()
                }
            }
        } header: {
            Text("Think Next")
                .sectionHeaderStyle()
        }
    }

    // MARK: - Nudge banners

    @ViewBuilder
    private var nudgesSection: some View {
        if !pendingNudges.isEmpty {
            Section {
                ForEach(pendingNudges.prefix(1)) { nudge in
                    MobileNudgeBanner(
                        nudge: nudge,
                        onOpen: {
                            database.attempt { db in
                                try Nudge.modify(nudge.id, in: db) { $0.status = .actedOn }
                            }
                            NudgeSettings.recordAction(type: nudge.type, actedOn: true)
                        },
                        onDismiss: {
                            database.attempt { db in
                                try Nudge.modify(nudge.id, in: db) { $0.status = .dismissed }
                            }
                            NudgeSettings.recordAction(type: nudge.type, actedOn: false)
                        }
                    )
                }
            } header: {
                Text("Nudges")
                    .sectionHeaderStyle()
            }
        }
    }

    // MARK: - Board picker sheet

    @ViewBuilder
    private var boardPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(boards) { board in
                    Button {
                        if let item = itemToAssign {
                            assignToBoard(item, board: board)
                        }
                        showBoardPicker = false
                        itemToAssign = nil
                    } label: {
                        Label(board.title, systemImage: board.icon ?? "folder")
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .navigationTitle("Move to Board")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showBoardPicker = false
                        itemToAssign = nil
                    }
                }
            }
        }
    }

    // MARK: - Inbox triage actions

    private func keepItem(_ item: ItemGraph) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        database.attempt { db in
            try Item.modify(item.id, in: db) {
                $0.status = .active
                $0.updatedAt = .now
            }
        }
    }

    private func dismissItem(_ item: ItemGraph) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        #endif
        database.attempt { db in
            try Item.modify(item.id, in: db) {
                $0.status = .dismissed
                $0.updatedAt = .now
            }
        }
    }

    private func assignToBoard(_ item: ItemGraph, board: Board) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        let viewModel = ItemViewModel()
        viewModel.assignToBoard(item.id, board: board)
    }

    private func confirmTag(_ tag: Tag) {
        database.attempt { db in
            try Tag.modify(tag.id, in: db) { $0.isAutoGenerated = false }
        }
    }

    private func dismissTag(_ tag: Tag, from item: ItemGraph) {
        database.attempt { db in
            try Item.removeTag(tag.id, fromItem: item.id, in: db)
            try Item.modify(item.id, in: db) { $0.updatedAt = .now }
        }
    }

    // MARK: - Conversation actions

    private func startConversation(with bubble: PromptBubble) {
        openConversation(
            with: bubble.prompt,
            seedItemIDs: bubble.clusterItemIDs
        )
    }

    private func startNewConversation() {
        openConversation(with: "")
    }

    private func startWriting(with prompt: String?) {
        let cleanedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleanedPrompt, !cleanedPrompt.isEmpty else {
            NotificationCenter.default.post(name: .groveNewNote, object: nil)
            return
        }
        NotificationCenter.default.post(name: .groveNewNoteWithPrompt, object: cleanedPrompt)
    }

    private func openConversation(with prompt: String, seedItemIDs: [UUID] = []) {
        guard entitlement.canUse(.dialectics) else {
            paywallPresentation = paywallCoordinator.present(
                feature: .dialectics,
                source: .dialecticsLimit
            )
            return
        }
        entitlement.recordUse(.dialectics)

        NotificationCenter.default.postConversationPrompt(
            ConversationPromptPayload(
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                seedItemIDs: seedItemIDs,
                // Starters are assistant-voiced questions the user answers
                // ("What's worth thinking through?"), so the prompt opens the
                // conversation as the assistant, not as the user's own message.
                injectionMode: .asAssistantGreeting
            )
        )
    }

    @ViewBuilder
    private func openItemRow<Content: View>(item: ItemGraph, @ViewBuilder content: () -> Content) -> some View {
        if let onOpenItem {
            Button {
                onOpenItem(item)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else if let selectedItem, let openedItem {
            Button {
                selectedItem.wrappedValue = item
                openedItem.wrappedValue = item
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else if let coordinator = readerCoordinator {
            Button {
                coordinator.selectedItem = item
                coordinator.openedItem = item
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: MobileItemRoute(id: item.id)) {
                content()
            }
            .buttonStyle(.plain)
        }
    }
}
