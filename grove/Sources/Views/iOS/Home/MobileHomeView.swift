import SwiftUI
import SwiftData

/// iOS Home screen — inbox triage, discussion suggestions, recent items, and nudge banners.
struct MobileHomeView: View {
    private static let maxDiscussionCards = 3

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Query(sort: \Item.lastEngagedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Item.createdAt, order: .reverse) private var allItemsByDate: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    @Environment(ConversationStarterService.self) private var starterService
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @State private var showSearch = false
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?
    @State private var selectedSuggestion: PromptBubble?
    @State private var paywallPresentation: PaywallPresentation?

    var onOpenItem: ((Item) -> Void)? = nil
    var selectedItem: Binding<Item?>? = nil
    var openedItem: Binding<Item?>? = nil

    private var inboxItems: [Item] {
        allItemsByDate.filter { $0.status == .inbox }
    }

    private var recentItems: [Item] {
        Array(allItems.filter { $0.status == .active || $0.status == .inbox }.prefix(6))
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

            inboxSection
            discussionSuggestionsSection
            recentItemsSection
            nudgesSection
        }
        .listStyle(.plain)
        .navigationTitle("Home")
        .navigationDestination(for: Item.self) { item in
            MobileItemReaderView(item: item)
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
        .onChange(of: allItems.count) { _, newCount in
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
            if horizontalSizeClass == .regular {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        regularDiscussionCard(bubble: newConversationBubble) {
                            startNewConversation()
                        }

                        ForEach(discussionBubbles) { bubble in
                            regularDiscussionCard(bubble: bubble) {
                                selectedSuggestion = bubble
                            }
                        }
                    }
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                }
                .listRowInsets(EdgeInsets())
            } else {
                MobileStarterCard(bubble: newConversationBubble) {
                    startNewConversation()
                }

                ForEach(discussionBubbles) { bubble in
                    MobileStarterCard(bubble: bubble) {
                        startConversation(with: bubble)
                    }
                }
            }
        } header: {
            Text("Discussion Suggestions")
                .sectionHeaderStyle()
        }
    }

    private func regularDiscussionCard(
        bubble: PromptBubble,
        onTap: @escaping () -> Void
    ) -> some View {
        MobileStarterCard(
            bubble: bubble,
            showsDisclosureIndicator: true,
            onTap: onTap
        )
        .frame(width: 300)
    }

    // MARK: - Recent items

    @ViewBuilder
    private var recentItemsSection: some View {
        if !recentItems.isEmpty {
            Section {
                ForEach(recentItems) { item in
                    openItemRow(item: item) {
                        MobileItemCardView(item: item)
                    }
                    .mobileItemContextMenu(item: item)
                }
            } header: {
                Text("Recent")
                    .sectionHeaderStyle()
            }
        }
    }

    // MARK: - Nudge banners

    @ViewBuilder
    private var nudgesSection: some View {
        if !pendingNudges.isEmpty {
            Section {
                ForEach(pendingNudges) { nudge in
                    MobileNudgeBanner(
                        nudge: nudge,
                        onOpen: {
                            nudge.status = .actedOn
                            try? modelContext.save()
                        },
                        onDismiss: {
                            withAnimation {
                                nudge.status = .dismissed
                                try? modelContext.save()
                            }
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

    private func keepItem(_ item: Item) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        withAnimation {
            item.status = .active
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func dismissItem(_ item: Item) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        #endif
        withAnimation {
            item.status = .dismissed
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func assignToBoard(_ item: Item, board: Board) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        let viewModel = ItemViewModel(modelContext: modelContext)
        viewModel.assignToBoard(item, board: board)
        item.status = .active
        item.updatedAt = .now
        try? modelContext.save()
    }

    private func confirmTag(_ tag: Tag) {
        tag.isAutoGenerated = false
        try? modelContext.save()
    }

    private func dismissTag(_ tag: Tag, from item: Item) {
        item.tags.removeAll { $0.id == tag.id }
        item.updatedAt = .now
        try? modelContext.save()
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
                injectionMode: .asAssistantGreeting
            )
        )
    }

    @ViewBuilder
    private func openItemRow<Content: View>(item: Item, @ViewBuilder content: () -> Content) -> some View {
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
            NavigationLink(value: item) {
                content()
            }
            .buttonStyle(.plain)
        }
    }
}
