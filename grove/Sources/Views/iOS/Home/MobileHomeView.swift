import SwiftUI
import SwiftData

/// iOS Today screen — capture, flashcards when due, the inbox, then the one
/// Think Next card.
struct MobileHomeView: View {
    private static let maxDiscussionCards = 1

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    /// Recently touched items for starter generation. Sorted by `updatedAt`:
    /// `lastEngagedAt` stopped being written when resurfacing was retired.
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Item.createdAt, order: .reverse) private var allItemsByDate: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @Environment(ConversationStarterService.self) private var starterService
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @State private var itemToAssign: Item?
    @State private var paywallPresentation: PaywallPresentation?

    var onOpenItem: ((Item) -> Void)? = nil
    var selectedItem: Binding<Item?>? = nil
    var openedItem: Binding<Item?>? = nil

    private var inboxItems: [Item] {
        allItemsByDate.filter { $0.status == .inbox && !$0.isFeedSuggestion }
    }

    private var discussionBubbles: [PromptBubble] {
        Array(starterService.bubbles.prefix(Self.maxDiscussionCards))
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
            .listRowBackground(Color.bgPrimary)

            inboxSection
            discussionSuggestionsSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationTitle("Today")
        .navigationDestination(for: MobileItemRoute.self) { route in
            MobileItemRouteDestinationView(route: route)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // The root view owns the one search sheet.
                    NotificationCenter.default.post(name: .groveToggleSearch, object: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        .sheet(item: $itemToAssign) { item in
            boardPickerSheet(for: item)
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
                        MobileInboxCard(item: item)
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                        dimensions[.leading]
                    }
                    .listRowBackground(Color.bgPrimary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            keepItem(item)
                        } label: {
                            Label("Keep", systemImage: "checkmark.circle")
                        }
                        .tint(Color.textPrimary)

                        Button {
                            itemToAssign = item
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
                        .tint(Color.textTertiary)
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
        if let bubble = discussionBubbles.first {
            Section {
                StarterCard(
                    bubble: bubble,
                    onOpenChat: { startConversation(with: bubble) },
                    onStartWriting: { startWriting(with: bubble.prompt) },
                    onDismiss: { starterService.dismiss(bubble, in: modelContext) }
                )
                .listRowBackground(Color.bgPrimary)
            } header: {
                Text("Think Next")
                    .sectionHeaderStyle()
            }
        }
    }

    // MARK: - Board picker sheet

    /// The app's one board picker, led by the item's stored suggestion.
    private func boardPickerSheet(for item: Item) -> some View {
        let decision = BoardSuggestionMetadata.decision(from: item)
        return BoardPickerView(
            boards: boards,
            mode: .add,
            suggestedName: decision?.suggestedName ?? item.suggestedBoard ?? "",
            recommendedBoardID: decision?.recommendedBoardID,
            alternativeBoardIDs: decision?.alternativeBoardIDs ?? [],
            onSelect: { board in
                assignToBoard(item, board: board)
            },
            onCreate: { name in
                createBoard(named: name, for: item)
            }
        )
    }

    // MARK: - Inbox triage actions

    private func keepItem(_ item: Item) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        withAnimation(reduceMotion ? nil : .default) {
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
        withAnimation(reduceMotion ? nil : .default) {
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
        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        let viewModel = ItemViewModel(modelContext: modelContext)
        viewModel.assignToBoard(item, board: board)
    }

    private func createBoard(named name: String, for item: Item) {
        let cleaned = BoardSuggestionEngine.cleanedBoardName(name)
        guard !cleaned.isEmpty else { return }
        if let existing = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
        }) {
            assignToBoard(item, board: existing)
        } else {
            let board = Board(title: cleaned)
            modelContext.insert(board)
            assignToBoard(item, board: board)
        }
    }

    // MARK: - Conversation actions

    private func startConversation(with bubble: PromptBubble) {
        openConversation(
            with: bubble.prompt,
            seedItemIDs: bubble.clusterItemIDs
        )
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
