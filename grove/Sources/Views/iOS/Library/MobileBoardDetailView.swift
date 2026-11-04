import SQLiteData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// iOS board detail.
/// - iPad regular width: mac-like board workspace with grid/list toggle, suggestions, and reorder.
/// - iPhone/compact width: simplified adaptive grid with navigation pushes.
struct MobileBoardDetailView: View {
    private static let maxDiscussionSuggestions = 2

#if os(iOS)
    @MainActor
    private enum Device {
        static let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    }
#endif

    /// The board as it was opened. Read `board`, which follows the library: a
    /// navigation destination can hold on to a copy that nothing refreshes.
    private let openedBoard: BoardGraph
    var onOpenItem: ((ItemGraph) -> Void)? = nil
    var selectedItem: Binding<ItemGraph?>? = nil
    var openedItem: Binding<ItemGraph?>? = nil

    @Dependency(\.defaultDatabase) private var database
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?

    @Fetch(Library.Request()) private var library = Library()

    @State private var localSelectedItem: ItemGraph?
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .dateAdded
    @State private var draggingItemID: UUID?
    @State private var itemToDelete: ItemGraph?
    @State private var isSuggestionsCollapsed = false
    @State private var starterService = ConversationStarterService.shared
    @State private var selectedSuggestion: PromptBubble?
    @State private var paywallPresentation: PaywallPresentation?
    @State private var showFlashcards = false

    init(
        board: BoardGraph,
        onOpenItem: ((ItemGraph) -> Void)? = nil,
        selectedItem: Binding<ItemGraph?>? = nil,
        openedItem: Binding<ItemGraph?>? = nil
    ) {
        openedBoard = board
        self.onOpenItem = onOpenItem
        self.selectedItem = selectedItem
        self.openedItem = openedItem
    }

    private var board: BoardGraph {
        library.board(openedBoard.id) ?? openedBoard
    }

    private var allItems: [ItemGraph] { library.items }

    private var isRegularSplitMode: Bool {
        horizontalSizeClass == .regular && (selectedItem != nil || openedItem != nil || readerCoordinator != nil)
    }

    private var selectedItemBinding: Binding<ItemGraph?> {
        if let selectedItem {
            return selectedItem
        }
        if let readerCoordinator {
            return Binding(
                get: { readerCoordinator.selectedItem },
                set: { readerCoordinator.selectedItem = $0 }
            )
        }
        return $localSelectedItem
    }

    private var openedItemBinding: Binding<ItemGraph?> {
        if let openedItem {
            return openedItem
        }
        if let readerCoordinator {
            return Binding(
                get: { readerCoordinator.openedItem },
                set: { readerCoordinator.openedItem = $0 }
            )
        }
        return .constant(nil)
    }

    private var effectiveItems: [ItemGraph] {
        Self.effectiveItems(for: board, allItems: allItems)
    }

    private var sortedFilteredItems: [ItemGraph] {
        Self.sortedItems(effectiveItems, for: board, sortOption: sortOption)
    }

    private var weekSections: [WeekSection]? {
        guard sortOption == .dateAdded, effectiveItems.count > 5 else { return nil }
        return WeekSection.group(sortedFilteredItems)
    }

    private var boardDiscussionSuggestions: [PromptBubble] {
        starterService.bubbles(for: board.id, maxResults: Self.maxDiscussionSuggestions)
    }

    private var compactColumns: [GridItem] {
        if usesMacStyleCompactCards {
            return [
                GridItem(
                    .adaptive(minimum: 300, maximum: 420),
                    spacing: Spacing.lg,
                    alignment: .top
                )
            ]
        }
        return [GridItem(.adaptive(minimum: 280), spacing: Spacing.md)]
    }

    @MainActor
    private var usesMacStyleCompactCards: Bool {
#if os(iOS)
        Device.isIPad
#else
        false
#endif
    }

    var body: some View {
        Group {
            if isRegularSplitMode {
                splitBoardLayout
            } else {
                compactBoardLayout
            }
        }
        .navigationTitle(board.title)
        .keepingCurrent($localSelectedItem, in: library)
        .keepingCurrent($itemToDelete, in: library)
        .navigationDestination(for: MobileItemRoute.self) { route in
            MobileItemRouteDestinationView(route: route)
        }
        .toolbar {
            toolbarCluster
            ToolbarItem(placement: .secondaryAction) {
                Button("Flashcards", systemImage: "rectangle.on.rectangle") { showFlashcards = true }
            }
        }
        .sheet(isPresented: $showFlashcards) {
            NavigationStack { FlashcardLibraryView(boardID: board.id) }
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
            viewMode = .grid
            selectedSuggestion = nil
        }
        .sheet(item: $selectedSuggestion) { suggestion in
            MobilePromptActionSheet(
                contextTitle: board.title,
                suggestion: suggestion,
                onOpenDialectics: {
                    startDialectic(with: suggestion)
                },
                onStartWriting: {
                    startWriting(with: suggestion.prompt)
                }
            )
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
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
                    // The iOS roots don't mount ContentViewHandlers, so the
                    // local bindings are cleared here before the shared
                    // deletion path runs.
                    if selectedItemBinding.wrappedValue?.id == item.id {
                        selectedItemBinding.wrappedValue = nil
                    }
                    if openedItemBinding.wrappedValue?.id == item.id {
                        openedItemBinding.wrappedValue = nil
                    }
                    ItemViewModel().deleteItem(item.id)
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Are you sure you want to delete \"\(item.title)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var splitBoardLayout: some View {
        VStack(spacing: 0) {
            if effectiveItems.isEmpty {
                emptyState
            } else {
                if !boardDiscussionSuggestions.isEmpty {
                    BoardSuggestionsView(
                        suggestions: boardDiscussionSuggestions,
                        isSuggestionsCollapsed: $isSuggestionsCollapsed,
                        onSelectSuggestion: { bubble in
                            selectedSuggestion = bubble
                        },
                        onRefresh: {
                            Task {
                                await starterService.forceRefreshBoard(board.id, items: allItems)
                            }
                        }
                    )
                }

                switch viewMode {
                case .grid:
                    BoardGridView(
                        items: sortedFilteredItems,
                        sections: weekSections,
                        canReorder: sortOption == .manual && !board.isSmart,
                        selectedItem: selectedItemBinding,
                        openedItem: openedItemBinding,
                        draggingItemID: $draggingItemID,
                        onOpenItem: onOpenItem,
                        itemContextMenu: { item in AnyView(itemContextMenu(for: item)) },
                        onReorder: moveGridItem
                    )
                case .list:
                    BoardListView(
                        items: sortedFilteredItems,
                        sections: weekSections,
                        canReorder: sortOption == .manual && !board.isSmart,
                        selectedItem: selectedItemBinding,
                        openedItem: openedItemBinding,
                        onOpenItem: onOpenItem,
                        itemContextMenu: { item in AnyView(itemContextMenu(for: item)) },
                        onMove: moveListItems
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var compactBoardLayout: some View {
        if sortedFilteredItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: compactColumns, spacing: Spacing.md) {
                    ForEach(sortedFilteredItems) { item in
                        NavigationLink(value: MobileItemRoute(id: item.id)) {
                            compactItemCard(for: item)
                        }
                        .buttonStyle(.plain)
                        .mobileItemContextMenu(item: item)
                    }
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.top, Spacing.md)
            }
        }
    }

    @ViewBuilder
    private func compactItemCard(for item: ItemGraph) -> some View {
        if usesMacStyleCompactCards {
            ItemCardView(item: item, showTags: true, usesContainerReadAction: true)
                .padding(.horizontal, Spacing.xs)
        } else {
            MobileItemCardView(item: item)
                .cardStyle()
                .padding(.horizontal, Spacing.xs)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(board.title, systemImage: board.icon ?? "tray")
        } description: {
            Text(board.isSmart
                ? "No items match this smart board yet."
                : "Items added to this board will appear here.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarCluster: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(BoardSortOption.allCases, id: \.self) { option in
                    if !(option == .manual && board.isSmart) {
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            if isRegularSplitMode {
                Button {
                    viewMode = viewMode == .grid ? .list : .grid
                } label: {
                    Label(viewMode == .grid ? "List" : "Grid", systemImage: viewMode.iconName)
                }
            }

            if isRegularSplitMode && sortOption == .manual && viewMode == .list && !board.isSmart {
#if os(iOS)
                EditButton()
#endif
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: ItemGraph) -> some View {
        Button {
            openItem(item)
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        if let urlString = item.sourceURL, let url = URL(string: urlString),
           item.metadata["videoLocalFile"] != "true" {
            Button {
                openItem(item)
            } label: {
                Label("Read in App", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                openURL(url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }

        Divider()

        if !board.isSmart {
            Button {
                let viewModel = ItemViewModel()
                viewModel.removeFromBoard(item.id, boardID: board.id)
            } label: {
                Label("Remove from Board", systemImage: "folder.badge.minus")
            }
        }

        Button(role: .destructive) {
            itemToDelete = item
        } label: {
            Label("Delete Item", systemImage: "trash")
        }
    }

    // MARK: - Suggestions

    private func startDialectic(with bubble: PromptBubble) {
        guard entitlement.canUse(.dialectics) else {
            paywallPresentation = paywallCoordinator.present(
                feature: .dialectics,
                source: .dialecticsLimit
            )
            return
        }
        entitlement.recordUse(.dialectics)

        let prompt = bubble.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let seedIDs = scopedSeedItemIDs(for: bubble)
        NotificationCenter.default.postConversationPrompt(
            ConversationPromptPayload(
                prompt: prompt,
                seedItemIDs: seedIDs,
                injectionMode: .asAssistantGreeting
            )
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

    private func scopedSeedItemIDs(for bubble: PromptBubble) -> [UUID] {
        let boardItemIDs = Set(effectiveItems.map(\.id))
        let scopedSeedIDs = bubble.clusterItemIDs.filter { boardItemIDs.contains($0) }
        return scopedSeedIDs.isEmpty ? bubble.clusterItemIDs : scopedSeedIDs
    }

    private func openItem(_ item: ItemGraph) {
        selectedItemBinding.wrappedValue = item
        if let onOpenItem {
            onOpenItem(item)
        } else {
            openedItemBinding.wrappedValue = item
        }
    }

    // MARK: - Reorder

    private func moveGridItem(fromID: UUID, toID: UUID) {
        guard !board.isSmart else { return }
        changeManualOrder { order in
            guard let fromIndex = order.firstIndex(of: fromID),
                  let toIndex = order.firstIndex(of: toID),
                  fromIndex != toIndex else { return }
            order.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    /// The offsets index the rows on screen, which are not the stored order: that
    /// also holds items the board doesn't show. So they become IDs here, while
    /// they still mean what the user dragged.
    private func moveListItems(from source: IndexSet, to destination: Int) {
        guard !board.isSmart else { return }
        let rows = sortedFilteredItems
        let movedIDs = source.filter { rows.indices.contains($0) }.map { rows[$0].id }
        let moved = Set(movedIDs)
        let nextID = rows.dropFirst(destination).first { !moved.contains($0.id) }?.id
        changeManualOrder { order in
            order.removeAll { moved.contains($0) }
            let index = nextID.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
            order.insert(contentsOf: movedIDs, at: index)
        }
    }

    /// Changes the manual order as the database has it now. `board` is behind a
    /// write until the library arrives, and a grid drag writes once per card it
    /// crosses, so an order built from `board` would undo the step before it.
    private func changeManualOrder(_ change: (inout [UUID]) -> Void) {
        let boardID = board.id
        database.attempt { db in
            guard let row = try Board.find(boardID).fetchOne(db) else { return }
            let items = try Item.where { $0.boardID.eq(boardID) }.fetchAll(db)
            var order = BoardGraph(board: row, items: items.map { ItemGraph(item: $0) }).manualOrder()
            let known = Set(order)
            let unordered = items.filter { !known.contains($0.id) }
            order.insert(contentsOf: unordered.sorted { $0.createdAt > $1.createdAt }.map(\.id), at: 0)
            change(&order)
            try Board.modify(boardID, in: db) { $0.itemOrder = order }
        }
    }

    // MARK: - Testable Data Helpers

    static func effectiveItems(for board: BoardGraph, allItems: [ItemGraph]) -> [ItemGraph] {
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
                .filter { $0.status == .active }
        }
        return board.items.filter { $0.status == .active }
    }

    static func sortedItems(_ items: [ItemGraph], for board: BoardGraph, sortOption: BoardSortOption) -> [ItemGraph] {
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
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .depthScore:
            return items.sorted { $0.depthScore > $1.depthScore }
        }
    }
}
