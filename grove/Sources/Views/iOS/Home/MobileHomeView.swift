import SwiftUI
import SwiftData

/// iOS Home screen — inbox triage, conversation starters, recent items, and nudge banners.
struct MobileHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.lastEngagedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Item.createdAt, order: .reverse) private var allItemsByDate: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    @State private var starterService = ConversationStarterService.shared
    @State private var dialecticsService = DialecticsService()
    @State private var showSearch = false
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?

    private var inboxItems: [Item] {
        allItemsByDate.filter { $0.status == .inbox }
    }

    private var recentItems: [Item] {
        Array(allItems.filter { $0.status == .active || $0.status == .inbox }.prefix(6))
    }

    private var pendingNudges: [Nudge] {
        allNudges.filter { $0.status == .pending || $0.status == .shown }
    }

    var body: some View {
        List {
            inboxSection
            startersSection
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
        .task {
            await starterService.refresh(items: allItems)
        }
    }

    // MARK: - Inbox section

    @ViewBuilder
    private var inboxSection: some View {
        if !inboxItems.isEmpty {
            Section {
                ForEach(inboxItems) { item in
                    MobileInboxCard(
                        item: item,
                        onConfirmTag: { tag in confirmTag(tag) },
                        onDismissTag: { tag in dismissTag(tag, from: item) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            queueItem(item)
                        } label: {
                            Label("Queue", systemImage: "text.badge.plus")
                        }
                        .tint(.blue)

                        Button {
                            itemToAssign = item
                            showBoardPicker = true
                        } label: {
                            Label("Board", systemImage: "folder")
                        }
                        .tint(.purple)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            archiveItem(item)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            dismissItem(item)
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    }
                }
            } header: {
                Text("Inbox")
                    .sectionHeaderStyle()
            }
        }
    }

    // MARK: - Conversation starters

    @ViewBuilder
    private var startersSection: some View {
        let bubbles = Array(starterService.bubbles.prefix(3))
        if !bubbles.isEmpty {
            Section {
                ForEach(bubbles) { bubble in
                    MobileStarterCard(bubble: bubble) {
                        startConversation(with: bubble)
                    }
                }
            } header: {
                Text("Conversation Starters")
                    .sectionHeaderStyle()
            }
        }
    }

    // MARK: - Recent items

    @ViewBuilder
    private var recentItemsSection: some View {
        if !recentItems.isEmpty {
            Section {
                ForEach(recentItems) { item in
                    NavigationLink(value: item) {
                        MobileItemCardView(item: item)
                    }
                    .buttonStyle(.plain)
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

    private func queueItem(_ item: Item) {
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

    private func archiveItem(_ item: Item) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
        withAnimation {
            item.status = .archived
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
        let seedItems = allItems.filter { bubble.clusterItemIDs.contains($0.id) }
        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: nil,
            context: modelContext
        )
        Task {
            _ = await dialecticsService.sendMessage(
                userText: bubble.prompt,
                conversation: conversation,
                context: modelContext
            )
        }
    }
}
