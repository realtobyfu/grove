import SwiftUI
import SwiftData

/// iOS Today screen — capture, flashcards when due, the stale-inbox banner, the
/// inbox, then the one Think Next card.
struct MobileHomeView: View {
    private static let maxDiscussionCards = 1

    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    /// Recently touched items for starter generation. Sorted by `updatedAt`:
    /// `lastEngagedAt` stopped being written when resurfacing was retired.
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Item.createdAt, order: .reverse) private var allItemsByDate: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    @Environment(ConversationStarterService.self) private var starterService
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @State private var showSearch = false
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?
    @State private var paywallPresentation: PaywallPresentation?

    var onOpenItem: ((Item) -> Void)? = nil
    var selectedItem: Binding<Item?>? = nil
    var openedItem: Binding<Item?>? = nil

    private var inboxItems: [Item] {
        allItemsByDate.filter { $0.status == .inbox && !$0.isFeedSuggestion }
    }

    /// Stale inbox is the only nudge type still generated; retired types left
    /// in a store are swept to `.dismissed` by NudgeEngine and never shown.
    private var pendingNudges: [Nudge] {
        allNudges.filter { $0.type == .staleInbox && ($0.status == .pending || $0.status == .shown) }
    }

    private var discussionBubbles: [PromptBubble] {
        Array(starterService.bubbles.prefix(Self.maxDiscussionCards))
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
                // One row, so the flashcards view stays mounted when it hides:
                // a List row can't collapse to nothing, and removing the view
                // would stop its due-date refresh and close its review sheet.
                VStack(spacing: 0) {
                    InlineCaptureBar()
                    LearningInvitationView(
                        showsOnlyWhenDue: true,
                        rowInsets: EdgeInsets(top: Spacing.sm, leading: 0, bottom: 0, trailing: 0)
                    )
                }
                .listRowInsets(EdgeInsets(
                    top: Spacing.sm,
                    leading: LayoutDimensions.contentPaddingH,
                    bottom: Spacing.sm,
                    trailing: LayoutDimensions.contentPaddingH
                ))
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)

            nudgesSection
            inboxSection
            discussionSuggestionsSection
        }
        .listStyle(.plain)
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
            if let bubble = discussionBubbles.first {
                StarterCard(
                    bubble: bubble,
                    onOpenChat: { startConversation(with: bubble) },
                    onStartWriting: { startWriting(with: bubble.prompt) },
                    onDismiss: { starterService.dismiss(bubble, in: modelContext) }
                )
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
                // Starters are assistant-voiced questions the user answers
                // ("What's worth thinking through?"), so the prompt opens the
                // conversation as the assistant, not as the user's own message.
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
            NavigationLink(value: MobileItemRoute(id: item.id)) {
                content()
            }
            .buttonStyle(.plain)
        }
    }
}
