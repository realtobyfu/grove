import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// iOS board detail.
/// - iPad regular width: mac-like board workspace with grid/list toggle, suggestions, synthesis, and reorder.
/// - iPhone/compact width: simplified adaptive grid with navigation pushes.
struct MobileBoardDetailView: View {
    private static let maxDiscussionSuggestions = 2

#if os(iOS)
    @MainActor
    private enum Device {
        static let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    }
#endif

    let board: Board
    var onOpenItem: ((Item) -> Void)? = nil
    var selectedItem: Binding<Item?>? = nil
    var openedItem: Binding<Item?>? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?

    @Query private var allItems: [Item]

    @State private var localSelectedItem: Item?
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .dateAdded
    @State private var draggingItemID: UUID?
    @State private var showSynthesisSheet = false
    @State private var showItemPicker = false
    @State private var pickedItems: [Item] = []
    @State private var itemToDelete: Item?
    @State private var isSuggestionsCollapsed = false
    @State private var starterService = ConversationStarterService.shared
    @State private var selectedSuggestion: PromptBubble?
    @State private var paywallPresentation: PaywallPresentation?

    private var isRegularSplitMode: Bool {
        horizontalSizeClass == .regular && (selectedItem != nil || openedItem != nil || readerCoordinator != nil)
    }

    private var selectedItemBinding: Binding<Item?> {
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

    private var openedItemBinding: Binding<Item?> {
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

    private var effectiveItems: [Item] {
        Self.effectiveItems(for: board, allItems: allItems)
    }

    private var sortedFilteredItems: [Item] {
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
        .navigationDestination(for: Item.self) { item in
            MobileItemReaderView(item: item)
        }
        .toolbar {
            toolbarCluster
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
        .sheet(isPresented: $showItemPicker, onDismiss: {
            if !pickedItems.isEmpty {
                showSynthesisSheet = true
            }
        }) {
            SynthesisItemPickerSheet(
                items: effectiveItems,
                scopeTitle: board.title,
                onConfirm: { items in
                    pickedItems = items
                }
            )
        }
        .sheet(isPresented: $showSynthesisSheet) {
            SynthesisSheet(
                items: pickedItems,
                scopeTitle: board.title,
                board: board,
                onCreated: { item in
                    openItem(item)
                }
            )
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
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
                    if selectedItemBinding.wrappedValue?.id == item.id {
                        selectedItemBinding.wrappedValue = nil
                    }
                    if openedItemBinding.wrappedValue?.id == item.id {
                        openedItemBinding.wrappedValue = nil
                    }
                    modelContext.delete(item)
                    try? modelContext.save()
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
                        NavigationLink(value: item) {
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
    private func compactItemCard(for item: Item) -> some View {
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

            Button {
                guard entitlement.canUse(.synthesis) else {
                    paywallPresentation = paywallCoordinator.present(
                        feature: .synthesis,
                        source: .synthesisAction
                    )
                    return
                }
                showItemPicker = true
            } label: {
                Label("Synthesize", systemImage: "sparkles")
            }
            .disabled(effectiveItems.count < AppConstants.Activity.synthesisMinItems)

            if isRegularSplitMode && sortOption == .manual && viewMode == .list && !board.isSmart {
#if os(iOS)
                EditButton()
#endif
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: Item) -> some View {
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
                let viewModel = ItemViewModel(modelContext: modelContext)
                viewModel.removeFromBoard(item, board: board)
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

    private func openItem(_ item: Item) {
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
        guard !board.isSmart else { return }
        var order = board.manualOrder()
        let allIDs = board.items.map(\.id)
        let known = Set(order)
        order.insert(contentsOf: allIDs.filter { !known.contains($0) }, at: 0)
        order.move(fromOffsets: source, toOffset: destination)
        board.setManualOrder(order)
        try? modelContext.save()
    }

    // MARK: - Testable Data Helpers

    static func effectiveItems(for board: Board, allItems: [Item]) -> [Item] {
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
                .filter { $0.status == .active }
        }
        return board.items.filter { $0.status == .active }
    }

    static func sortedItems(_ items: [Item], for board: Board, sortOption: BoardSortOption) -> [Item] {
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
