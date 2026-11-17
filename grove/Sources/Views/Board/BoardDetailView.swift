#if os(macOS)
import AppKit
#endif
import SwiftUI
import SwiftData

enum BoardViewMode: String, CaseIterable, Sendable {
    case grid
    case list

    var iconName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

enum BoardSortOption: String, CaseIterable, Sendable {
    case manual = "Manual"
    case dateAdded = "Date Added"
    case title = "Title"
}

struct BoardDetailView: View {
    private static let maxDiscussionSuggestions = 2

    let board: Board
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .manual
    @State private var draggingItemID: UUID?
    @State private var itemToDelete: Item?
    @State private var isSuggestionsCollapsed = false
    @State private var starterService = ConversationStarterService.shared
    @State private var paywallPresentation: PaywallPresentation?

    /// The active items that belong to this board.
    private var effectiveItems: [Item] {
        board.items.filter { $0.status == .active }
    }

    private var sortedFilteredItems: [Item] {
        sortItems(effectiveItems)
    }

    private var weekSections: [WeekSection]? {
        guard sortOption == .dateAdded, effectiveItems.count > 5 else { return nil }
        return WeekSection.group(sortedFilteredItems)
    }

    private var boardDiscussionSuggestions: [PromptBubble] {
        starterService.bubbles(for: board.id, maxResults: Self.maxDiscussionSuggestions)
    }

    // MARK: - Header Helper

    private var headerView: BoardDetailHeaderView {
        BoardDetailHeaderView(
            board: board,
            displayedItems: sortedFilteredItems,
            boardDiscussionSuggestions: boardDiscussionSuggestions,
            sortOption: sortOption,
            viewMode: $viewMode,
            sortOptionBinding: $sortOption,
            isSuggestionsCollapsed: $isSuggestionsCollapsed,
            onOpenChat: { startDialectic(with: $0) },
            onStartWriting: { startWriting(with: $0.prompt) },
            onRefreshSuggestions: {
                Task {
                    await starterService.forceRefreshBoard(board.id, items: allItems)
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            CaptureBarView(currentBoardID: board.id)

            LearningInvitationView(boardID: board.id)
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.vertical, Spacing.md)

            if effectiveItems.isEmpty {
                headerView.emptyState
            } else {
                headerView.suggestionsBar

                BoardItemListView(
                    board: board,
                    sortedFilteredItems: sortedFilteredItems,
                    weekSections: weekSections,
                    canReorder: sortOption == .manual,
                    viewMode: viewMode,
                    selectedItem: $selectedItem,
                    openedItem: $openedItem,
                    draggingItemID: $draggingItemID,
                    itemToDelete: $itemToDelete,
                    onMoveGrid: moveGridItem,
                    onMoveList: moveListItems
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(board.title)
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                headerView.toolbarCluster
            }
        }
        .onKeyPress(phases: [.down]) { keyPress in
            handleBoardKeyPress(keyPress)
        }
        .onKeyPress(.return) {
            guard canHandleBoardShortcuts else { return .ignored }
            openSelectedItem()
            return .handled
        }
        .task(id: board.id) {
            await starterService.refreshBoard(board.id, items: allItems)
        }
        .onChange(of: allItems.count) { _, newCount in
            guard newCount > 0, boardDiscussionSuggestions.isEmpty else { return }
            Task {
                await starterService.refreshBoard(board.id, items: allItems)
            }
        }
        .onChange(of: board.id, initial: true) {
            sortOption = .dateAdded
        }
        .alert(
            "Delete Item",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    // Presentation state (selection, reader, write panel) is
                    // cleared by the .groveItemWillDelete observer.
                    ItemViewModel(modelContext: modelContext).deleteItem(item)
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Are you sure you want to delete \"\(item.title)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Suggestions

    private func startDialectic(with bubble: PromptBubble) {
        let prompt = bubble.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            openConversation(with: "")
            return
        }
        openConversation(with: prompt, seedItemIDs: scopedSeedItemIDs(for: bubble))
    }

    private func startWriting(with prompt: String?) {
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NotificationCenter.default.post(name: .groveNewNote, object: nil)
            return
        }
        NotificationCenter.default.post(name: .groveNewNoteWithPrompt, object: prompt)
    }

    private func openConversation(with prompt: String, seedItemIDs: [UUID] = []) {
        NotificationCenter.default.postConversationPrompt(
            ConversationPromptPayload(
                prompt: prompt,
                seedItemIDs: seedItemIDs,
                injectionMode: .asAssistantGreeting
            )
        )
    }

    private func scopedSeedItemIDs(for bubble: PromptBubble) -> [UUID] {
        let boardItemIDs = Set(effectiveItems.map(\.id))
        let scopedSeedIDs = bubble.clusterItemIDs.filter { boardItemIDs.contains($0) }
        return scopedSeedIDs.isEmpty ? bubble.clusterItemIDs : scopedSeedIDs
    }

    // MARK: - Keyboard Handlers

    private var canHandleBoardShortcuts: Bool {
        !isTextInputFocusedInKeyWindow
    }

    private var isTextInputFocusedInKeyWindow: Bool {
        #if os(macOS)
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        if firstResponder is NSTextView { return true }
        guard let responderView = firstResponder as? NSView else { return false }
        return responderView.conforms(to: NSTextInputClient.self)
        #else
        return false
        #endif
    }

    private func handleBoardKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard canHandleBoardShortcuts else { return .ignored }
        guard keyPress.modifiers.isEmpty else { return .ignored }

        switch keyPress.characters.lowercased() {
        case "j":
            navigateItems(by: 1)
            return .handled
        case "k":
            navigateItems(by: -1)
            return .handled
        default:
            return .ignored
        }
    }

    private func navigateItems(by offset: Int) {
        let items = sortedFilteredItems
        guard !items.isEmpty else { return }

        if let current = selectedItem,
           let currentIndex = items.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            selectedItem = items[newIndex]
        } else {
            selectedItem = offset > 0 ? items.first : items.last
        }
    }

    private func openSelectedItem() {
        guard let item = selectedItem else { return }
        openedItem = item
    }

    // MARK: - Sort & Reorder

    private func sortItems(_ items: [Item]) -> [Item] {
        switch sortOption {
        case .manual:
            let order = board.manualOrder()
            let orderedItems = order.compactMap { id in items.first(where: { $0.id == id }) }
            let unorderedIDs = Set(items.map(\.id)).subtracting(Set(order))
            let unordered = items.filter { unorderedIDs.contains($0.id) }
            return unordered.sorted { $0.createdAt > $1.createdAt } + orderedItems
        case .dateAdded:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    private func moveGridItem(fromID: UUID, toID: UUID) {
        var order = board.manualOrder()
        let allIDs = board.items.map(\.id)
        let known = Set(order)
        order.insert(contentsOf: allIDs.filter { !known.contains($0) }, at: 0)
        guard let fromIndex = order.firstIndex(of: fromID),
              let toIndex = order.firstIndex(of: toID),
              fromIndex != toIndex else { return }
        order.move(fromOffsets: IndexSet(integer: fromIndex),
                   toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        board.setManualOrder(order)
        try? modelContext.save()
    }

    private func moveListItems(from source: IndexSet, to destination: Int) {
        var order = board.manualOrder()
        let allIDs = board.items.map(\.id)
        let known = Set(order)
        order.insert(contentsOf: allIDs.filter { !known.contains($0) }, at: 0)
        order.move(fromOffsets: source, toOffset: destination)
        board.setManualOrder(order)
        try? modelContext.save()
    }
}

// MARK: - Grid Drop Delegate

struct BoardGridDropDelegate: DropDelegate {
    let targetItemID: UUID
    @Binding var draggingItemID: UUID?
    let isEnabled: Bool
    let onReorder: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingItemID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return DropProposal(operation: .forbidden) }
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled,
              let from = draggingItemID,
              from != targetItemID else { return }
        onReorder(from, targetItemID)
    }
}
