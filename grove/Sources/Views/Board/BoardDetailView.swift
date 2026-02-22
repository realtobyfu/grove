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
    private static let maxDiscussionSuggestions = 3

    private struct PromptModeSelection {
        let prompt: String
        let label: String
        let scopedSeedItemIDs: [UUID]

        init(bubble: PromptBubble, scopedSeedItemIDs: [UUID]) {
            self.prompt = bubble.prompt
            self.label = bubble.label
            self.scopedSeedItemIDs = scopedSeedItemIDs
        }
    }

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
    @State private var starterService = ConversationStarterService.shared
    @State private var promptModeSelection: PromptModeSelection?

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

    private var boardDiscussionSuggestions: [PromptBubble] {
        let effectiveItemIDs = Set(effectiveItems.map(\.id))
        let scoped = starterService.bubbles.filter { bubble in
            if bubble.boardIDs.contains(board.id) {
                return true
            }
            guard !bubble.clusterItemIDs.isEmpty else { return false }
            return !effectiveItemIDs.isDisjoint(with: bubble.clusterItemIDs)
        }
        return Array(scoped.prefix(Self.maxDiscussionSuggestions))
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if !board.isSmart {
                    CaptureBarView(currentBoardID: board.id)
                }

                if effectiveItems.isEmpty {
                    emptyState
                } else {
                    if !boardDiscussionSuggestions.isEmpty {
                        BoardSuggestionsView(
                            suggestions: boardDiscussionSuggestions,
                            isSuggestionsCollapsed: $isSuggestionsCollapsed,
                            onSelectSuggestion: presentPromptActions(for:)
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

            if let selection = promptModeSelection {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(width: 1)

                promptModePanel(for: selection)
                    .frame(width: 330)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
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
        .onKeyPress(phases: [.down]) { keyPress in
            handleBoardKeyPress(keyPress)
        }
        .onKeyPress(.return) {
            guard canHandleBoardShortcuts else { return .ignored }
            openSelectedItem()
            return .handled
        }
        .task {
            await starterService.refresh(items: allItems)
        }
        .onChange(of: board.id, initial: true) {
            sortOption = board.isSmart ? .dateAdded : .manual
            promptModeSelection = nil
        }
        .animation(.easeInOut(duration: 0.2), value: promptModeSelection != nil)
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

    private func presentPromptActions(for bubble: PromptBubble) {
        withAnimation(.easeInOut(duration: 0.2)) {
            promptModeSelection = PromptModeSelection(
                bubble: bubble,
                scopedSeedItemIDs: scopedSeedItemIDs(for: bubble)
            )
        }
    }

    private func promptModePanel(for selection: PromptModeSelection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Text("PROMPT ACTIONS")
                    .sectionHeaderStyle()

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        promptModeSelection = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(8)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close prompt actions")
                .accessibilityHint("Return to board without opening an action.")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(selection.label.uppercased())
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)

                Text(selection.prompt)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.md)

            VStack(spacing: Spacing.sm) {
                Button {
                    startDialectic(with: selection)
                } label: {
                    Label("Open Dialectics", systemImage: "bubble.left.and.bubble.right")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    startWriting(with: selection.prompt)
                } label: {
                    Label("Start Writing", systemImage: "square.and.pencil")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)

            Spacer(minLength: 0)
        }
        .background(Color.bgInspector)
    }

    private func startDialectic(with selection: PromptModeSelection) {
        defer { promptModeSelection = nil }
        let prompt = selection.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            openConversation(with: "")
            return
        }
        openConversation(with: prompt, seedItemIDs: selection.scopedSeedItemIDs)
    }

    private func startWriting(with prompt: String?) {
        defer { promptModeSelection = nil }
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
        !showItemPicker && !showSynthesisSheet && !isTextInputFocusedInKeyWindow
    }

    private var isTextInputFocusedInKeyWindow: Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        if firstResponder is NSTextView { return true }
        guard let responderView = firstResponder as? NSView else { return false }
        return responderView.conforms(to: NSTextInputClient.self)
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
