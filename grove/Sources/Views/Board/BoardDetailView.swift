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
    @State private var selectedFilterTags: Set<UUID> = []
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
        }
        return board.items
    }

    /// Flat ordered list of all visible items for J/K navigation
    private var flatVisibleItems: [Item] {
        sortedFilteredItems
    }

    // MARK: - Computed Properties

    private var allBoardTags: [Tag] {
        var tagSet: [UUID: Tag] = [:]
        for item in effectiveItems {
            for tag in item.tags {
                tagSet[tag.id] = tag
            }
        }
        return tagSet.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var filteredItems: [Item] {
        guard !selectedFilterTags.isEmpty else { return effectiveItems }
        return effectiveItems.filter { item in
            let itemTagIDs = Set(item.tags.map(\.id))
            return selectedFilterTags.isSubset(of: itemTagIDs)
        }
    }

    private var sortedFilteredItems: [Item] {
        sortItems(filteredItems)
    }

    private var activeNudgesForBoard: [Nudge] {
        let boardItemIDs = Set(effectiveItems.map(\.id))
        return allNudges
            .filter { ($0.status == .pending || $0.status == .shown) && $0.targetItem != nil && boardItemIDs.contains($0.targetItem!.id) }
    }

    private func computeBoardSuggestions() -> [Suggestion] {
        var result: [Suggestion] = []
        let items = effectiveItems

        // Active nudge targeting items in this board
        if let nudge = activeNudgesForBoard.first {
            result.append(Suggestion(
                type: .nudge,
                title: nudge.displayMessage,
                reason: nudge.type.actionLabel,
                item: nudge.targetItem,
                nudge: nudge
            ))
        }

        // Reflect — items with content but no reflections
        let reflectCandidates = items
            .filter { $0.status == .active && $0.content != nil && !$0.content!.isEmpty && $0.reflections.isEmpty }
            .sorted { $0.depthScore > $1.depthScore }
        if let top = reflectCandidates.first {
            result.append(Suggestion(type: .reflect, title: top.title, reason: "Has content but no reflections yet", item: top))
        }

        // Revisit — overdue items in this board
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

    var body: some View {
        VStack(spacing: 0) {
            // Capture bar — auto-assigns to this board
            if !board.isSmart {
                CaptureBarView(currentBoardID: board.id)
            }

            if effectiveItems.isEmpty {
                emptyState
            } else {
                // Suggestions section
                if !boardSuggestions.isEmpty {
                    boardSuggestionsSection
                }

                // Tag filter bar
                if !allBoardTags.isEmpty {
                    tagFilterBar
                }

                // Content
                switch viewMode {
                case .grid:
                    gridView
                case .list:
                    listView
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
                items: filteredItems,
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
                    if selectedItem?.id == item.id {
                        selectedItem = nil
                    }
                    if openedItem?.id == item.id {
                        openedItem = nil
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

    // MARK: - Keyboard Handlers (J/K/Enter)

    private var boardKeyboardHandlers: some View {
        Group {
            // J — select next item
            Button("") { navigateItems(by: 1) }
                .keyboardShortcut("j", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // K — select previous item
            Button("") { navigateItems(by: -1) }
                .keyboardShortcut("k", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // Enter — open selected item
            Button("") { openSelectedItem() }
                .keyboardShortcut(.return, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    private func navigateItems(by offset: Int) {
        let items = flatVisibleItems
        guard !items.isEmpty else { return }

        if let current = selectedItem,
           let currentIndex = items.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            selectedItem = items[newIndex]
        } else {
            // No selection — select first or last depending on direction
            selectedItem = offset > 0 ? items.first : items.last
        }
    }

    private func openSelectedItem() {
        guard let item = selectedItem else { return }
        openedItem = item
    }

    // MARK: - Board Suggestions Section

    private var boardSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "Suggestions",
                count: boardSuggestions.count,
                isCollapsed: $isSuggestionsCollapsed
            )

            if !isSuggestionsCollapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 350), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(boardSuggestions) { suggestion in
                        boardSuggestionCard(suggestion)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
    }

    private func boardSuggestionCard(_ suggestion: Suggestion) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentSelection)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(suggestion.type == .nudge ? (suggestion.nudge?.type.actionLabel ?? "NUDGE").uppercased() : suggestion.type.rawValue)
                        .font(.groveBadge)
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()

                    if let nudge = suggestion.nudge {
                        Button {
                            dismissBoardNudge(nudge)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: suggestion.nudge?.type.iconName ?? suggestion.type.systemImage)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                    Text(suggestion.title)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                }

                if let nudge = suggestion.nudge {
                    Button {
                        actOnBoardNudge(nudge)
                    } label: {
                        Text(nudge.type.actionLabel)
                            .font(.groveBadge)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentBadge)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(suggestion.reason)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if suggestion.nudge != nil {
                // nudge cards have their own Button — do nothing on background tap
            } else if suggestion.type == .reflect, let item = suggestion.item {
                let prompt = "What are your key thoughts on \"\(item.title)\"?"
                NotificationCenter.default.post(name: .groveNewNoteWithPrompt, object: prompt)
            } else if let item = suggestion.item {
                openedItem = item
                selectedItem = item
            }
        }
    }

    private func actOnBoardNudge(_ nudge: Nudge) {
        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .actedOn
            NudgeSettings.recordAction(type: nudge.type, actedOn: true)
            try? modelContext.save()
        }
        if let item = nudge.targetItem {
            openedItem = item
            selectedItem = item
        }
        refreshBoardSuggestions()
    }

    private func dismissBoardNudge(_ nudge: Nudge) {
        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .dismissed
            NudgeSettings.recordAction(type: nudge.type, actedOn: false)
            try? modelContext.save()
        }
        refreshBoardSuggestions()
    }

    // MARK: - Tag Filter Bar

    private var tagFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allBoardTags) { tag in
                        let isActive = selectedFilterTags.contains(tag.id)
                        Button {
                            if isActive {
                                selectedFilterTags.remove(tag.id)
                            } else {
                                selectedFilterTags.insert(tag.id)
                            }
                        } label: {
                            Text(tag.name)
                                .font(.groveTag)
                                .foregroundStyle(isActive ? Color.textInverse : Color.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isActive ? Color.bgTagActive : Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if !selectedFilterTags.isEmpty {
                        Button {
                            selectedFilterTags.removeAll()
                        } label: {
                            Text("Clear")
                                .font(.groveBodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Spacing.sm)
            }
            Divider()
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

    // MARK: - Grid View

    private var gridView: some View {
        let canReorder = sortOption == .manual && !board.isSmart
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 420), spacing: Spacing.lg)],
                spacing: Spacing.lg
            ) {
                ForEach(sortedFilteredItems) { item in
                    ItemCardView(item: item, showTags: false, onReadInApp: {
                        openedItem = item
                        selectedItem = item
                    })
                    .opacity(canReorder && draggingItemID == item.id ? 0.4 : 1)
                    .onTapGesture(count: 2) {
                        openedItem = item
                        selectedItem = item
                    }
                    .onTapGesture(count: 1) {
                        selectedItem = item
                    }
                    .selectedItemStyle(selectedItem?.id == item.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .contextMenu { itemContextMenu(for: item) }
                    .onDrag {
                        guard canReorder else { return NSItemProvider() }
                        draggingItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: BoardGridDropDelegate(
                        targetItemID: item.id,
                        draggingItemID: $draggingItemID,
                        isEnabled: canReorder,
                        onReorder: moveGridItem
                    ))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: sortedFilteredItems.map(\.id))
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - List View

    @ViewBuilder
    private var listView: some View {
        if sortOption == .manual && !board.isSmart {
            List {
                ForEach(sortedFilteredItems) { item in
                    listRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            openedItem = item
                            selectedItem = item
                        }
                        .onTapGesture(count: 1) {
                            selectedItem = item
                        }
                        .selectedItemStyle(selectedItem?.id == item.id)
                        .contextMenu { itemContextMenu(for: item) }
                }
                .onMove(perform: moveListItems)
            }
            .listStyle(.plain)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sortedFilteredItems) { item in
                        listRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openedItem = item
                                selectedItem = item
                            }
                            .onTapGesture(count: 1) {
                                selectedItem = item
                            }
                            .selectedItemStyle(selectedItem?.id == item.id)
                            .transition(.opacity.combined(with: .slide))
                            .contextMenu { itemContextMenu(for: item) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: sortedFilteredItems.map(\.id))
                .padding()
            }
        }
    }

    private func listRow(item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                if let url = item.sourceURL {
                    Text(url)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            GrowthStageIndicator(stage: item.growthStage)
                .help("\(item.growthStage.displayName) — \(item.depthScore) pts")

            let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
            if connectionCount > 0 {
                Label("\(connectionCount)", systemImage: "link")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }

            if item.reflections.count > 0 {
                Label("\(item.reflections.count)", systemImage: "text.alignleft")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var synthesisButton: some View {
        Button {
            pickedItems = []
            showItemPicker = true
        } label: {
            Label("Synthesize", systemImage: "sparkles")
        }
        .buttonStyle(.bordered)
        .help("Generate an AI synthesis note from items in this board")
        .disabled(effectiveItems.count < 2)
    }

    private var addNoteButton: some View {
        Button {
            NotificationCenter.default.post(name: .groveNewNote, object: nil)
        } label: {
            Label("New Note", systemImage: "square.and.pencil")
        }
        .labelStyle(.iconOnly)
        .help("Add a new note to this board")
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

    private var smartBoardRuleIcon: some View {
        Image(systemName: "gearshape.2")
            .help("Smart board rules: \(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))")
    }

    @ViewBuilder
    private var boardToolbarCluster: some View {
        HStack(spacing: Spacing.sm) {
            sortPicker
            viewModeButton
            synthesisButton
            if board.isSmart && !board.smartRuleTags.isEmpty {
                smartBoardRuleIcon
            }
        }
    }

    // MARK: - Video Drag-and-Drop

    private func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                let path = url.path
                guard ItemViewModel.isSupportedVideoFile(path) else { return }
                nonisolated(unsafe) let context = modelContext
                nonisolated(unsafe) let boardRef = board
                Task { @MainActor in
                    let viewModel = ItemViewModel(modelContext: context)
                    let item = viewModel.createVideoItem(filePath: path, board: boardRef.isSmart ? nil : boardRef)
                    selectedItem = item
                }
            }
            handled = true
        }
        return handled
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

    // MARK: - Reorder

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
