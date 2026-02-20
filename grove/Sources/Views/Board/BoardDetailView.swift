import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    case depthScore = "Depth"
}

struct BoardDetailView: View {
    let board: Board
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .manual
    @State private var draggingItemID: UUID?
    @State private var showSynthesisSheet = false
    @State private var showItemPicker = false
    @State private var pickedItems: [Item] = []
    @State private var itemToDelete: Item?
    @State private var isSuggestionsCollapsed = false
    @State private var boardSuggestions: [Suggestion] = []
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    /// The effective items for this board — smart boards compute from tag rules, regular boards use direct membership
    private var effectiveItems: [Item] {
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
                .filter { $0.status == .active }
        }
        return board.items.filter { $0.status == .active }
    }

    private var sortedFilteredItems: [Item] {
        sortItems(effectiveItems)
    }

    private var activeNudgesForBoard: [Nudge] {
        let boardItemIDs = Set(effectiveItems.map(\.id))
        return allNudges
            .filter { ($0.status == .pending || $0.status == .shown) && $0.targetItem != nil && boardItemIDs.contains($0.targetItem!.id) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !board.isSmart {
                CaptureBarView(currentBoardID: board.id)
            }

            if effectiveItems.isEmpty {
                emptyState
            } else {
                if !boardSuggestions.isEmpty {
                    BoardSuggestionsView(
                        suggestions: boardSuggestions,
                        isSuggestionsCollapsed: $isSuggestionsCollapsed,
                        openedItem: $openedItem,
                        selectedItem: $selectedItem,
                        onRefresh: refreshBoardSuggestions
                    )
                }

                switch viewMode {
                case .grid:
                    BoardGridView(
                        items: sortedFilteredItems,
                        canReorder: sortOption == .manual && !board.isSmart,
                        selectedItem: $selectedItem,
                        openedItem: $openedItem,
                        draggingItemID: $draggingItemID,
                        itemContextMenu: { item in AnyView(itemContextMenu(for: item)) },
                        onReorder: moveGridItem
                    )
                case .list:
                    BoardListView(
                        items: sortedFilteredItems,
                        canReorder: sortOption == .manual && !board.isSmart,
                        selectedItem: $selectedItem,
                        openedItem: $openedItem,
                        itemContextMenu: { item in AnyView(itemContextMenu(for: item)) },
                        onMove: moveListItems
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleVideoDrop(providers: providers)
        }
        .navigationTitle(board.title)
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
                    selectedItem = item
                    openedItem = item
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                boardToolbarCluster
            }
        }
        .background(boardKeyboardHandlers)
        .task {
            if boardSuggestions.isEmpty {
                refreshBoardSuggestions()
            }
        }
        .onChange(of: effectiveItems.count) {
            refreshBoardSuggestions()
        }
        .onChange(of: board.id, initial: true) {
            sortOption = board.isSmart ? .dateAdded : .manual
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
                    if selectedItem?.id == item.id { selectedItem = nil }
                    if openedItem?.id == item.id { openedItem = nil }
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

    // MARK: - Suggestions

    private func computeBoardSuggestions() -> [Suggestion] {
        var result: [Suggestion] = []
        let items = effectiveItems

        if let nudge = activeNudgesForBoard.first {
            result.append(Suggestion(
                type: .nudge,
                title: nudge.displayMessage,
                reason: nudge.type.actionLabel,
                item: nudge.targetItem,
                nudge: nudge
            ))
        }

        let reflectCandidates = items
            .filter { $0.status == .active && $0.content != nil && !$0.content!.isEmpty && $0.reflections.isEmpty }
            .sorted { $0.depthScore > $1.depthScore }
        if let top = reflectCandidates.first {
            result.append(Suggestion(type: .reflect, title: top.title, reason: "Has content but no reflections yet", item: top))
        }

        let revisitCandidates = items
            .filter { $0.isResurfacingOverdue }
            .sorted { $0.depthScore > $1.depthScore }
        if let top = revisitCandidates.first {
            result.append(Suggestion(type: .revisit, title: top.title, reason: "Due for spaced review", item: top))
        }

        return Array(result.prefix(3))
    }

    private func refreshBoardSuggestions() {
        boardSuggestions = computeBoardSuggestions()
    }

    // MARK: - Keyboard Handlers

    private var boardKeyboardHandlers: some View {
        Group {
            Button("") { navigateItems(by: 1) }
                .keyboardShortcut("j", modifiers: [])
                .opacity(0).frame(width: 0, height: 0)

            Button("") { navigateItems(by: -1) }
                .keyboardShortcut("k", modifiers: [])
                .opacity(0).frame(width: 0, height: 0)

            Button("") { if let item = selectedItem { openedItem = item } }
                .keyboardShortcut(.return, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: board.isSmart ? "sparkles.rectangle.stack" : (board.icon ?? "square.grid.2x2"))
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text(board.title)
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            if board.isSmart {
                Text("No items match the tag rules yet. Tag items to see them appear here automatically.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if !board.smartRuleTags.isEmpty {
                    HStack(spacing: 4) {
                        Text("Rules:")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                        Text(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("No items yet. Add items to this board to get started.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var synthesisButton: some View {
        Button {
            pickedItems = []
            showItemPicker = true
        } label: {
            Label("Synthesize", systemImage: "sparkles")
        }
        .buttonStyle(.bordered)
        .help("Generate an AI synthesis note from items in this board")
        .disabled(effectiveItems.count < AppConstants.Activity.synthesisMinItems)
    }

    private var sortPicker: some View {
        Menu {
            ForEach(BoardSortOption.allCases, id: \.self) { option in
                if option == .manual && board.isSmart { EmptyView() } else {
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
        .buttonStyle(.bordered)
        .help("Sort items (\(sortOption.rawValue))")
    }

    private var viewModeButton: some View {
        Button {
            viewMode = viewMode == .grid ? .list : .grid
        } label: {
            Label(viewMode == .grid ? "List" : "Grid", systemImage: viewMode.iconName)
        }
        .buttonStyle(.bordered)
        .help(viewMode == .grid ? "Switch to list view" : "Switch to grid view")
    }

    @ViewBuilder
    private var boardToolbarCluster: some View {
        HStack(spacing: Spacing.sm) {
            sortPicker
            viewModeButton
            synthesisButton
            if board.isSmart && !board.smartRuleTags.isEmpty {
                Image(systemName: "gearshape.2")
                    .help("Smart board rules: \(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))")
            }
        }
    }

    // MARK: - Item Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: Item) -> some View {
        Button {
            openedItem = item
            selectedItem = item
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        if let urlString = item.sourceURL, let url = URL(string: urlString),
           item.metadata["videoLocalFile"] != "true" {
            Button {
                openedItem = item
                selectedItem = item
            } label: {
                Label("Read in App", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                NSWorkspace.shared.open(url)
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

    // MARK: - Video Drag-and-Drop

    private func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                let path = url.path
                guard CaptureService.isSupportedVideoFile(path) else { return }
                Task { @MainActor in
                    let captureService = CaptureService(modelContext: modelContext)
                    let item = captureService.createVideoItem(filePath: path, board: board.isSmart ? nil : board)
                    selectedItem = item
                }
            }
            handled = true
        }
        return handled
    }

    // MARK: - Sort & Reorder

    private func sortItems(_ items: [Item]) -> [Item] {
        switch sortOption {
        case .manual:
            let order = board.manualOrder()
            let orderedItems = order.compactMap { id in items.first(where: { $0.id == id }) }
            let unorderedIDs = Set(items.map(\.id)).subtracting(Set(order))
            let unordered = items.filter { unorderedIDs.contains($0.id) }
            return orderedItems + unordered
        case .dateAdded:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .depthScore:
            return items.sorted { $0.depthScore > $1.depthScore }
        }
    }

    private func moveGridItem(fromID: UUID, toID: UUID) {
        guard !board.isSmart else { return }
        var order = board.manualOrder()
        let allIDs = board.items.map(\.id)
        let known = Set(order)
        order.append(contentsOf: allIDs.filter { !known.contains($0) })
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
        order.append(contentsOf: allIDs.filter { !known.contains($0) })
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

// MARK: - New Note Sheet

struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""

    let onCreate: (String, String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Note")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Title") {
                    TextField("Note title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.groveBody)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .font(.groveBody)
                        .frame(minHeight: 150)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let noteTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Untitled Note"
                        : title
                    let noteContent = content.isEmpty ? nil : content
                    onCreate(noteTitle, noteContent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440, height: 400)
    }
}
