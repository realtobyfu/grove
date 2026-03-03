#if os(macOS)
import AppKit
#endif
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
    private static let maxDiscussionSuggestions = 2

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
    @State private var promptModePanelWidth: CGFloat = LayoutSettings.width(for: .boardPrompt) ?? 330
    @State private var paywallPresentation: PaywallPresentation?

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
            effectiveItems: effectiveItems,
            boardDiscussionSuggestions: boardDiscussionSuggestions,
            sortOption: sortOption,
            viewMode: $viewMode,
            sortOptionBinding: $sortOption,
            showItemPicker: $showItemPicker,
            isSuggestionsCollapsed: $isSuggestionsCollapsed,
            paywallPresentation: $paywallPresentation,
            onSelectSuggestion: presentPromptActions(for:),
            onRefreshSuggestions: {
                Task {
                    await starterService.forceRefreshBoard(board.id, items: allItems)
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let minPanelWidth: CGFloat = 280
            let maxPanelWidth = max(minPanelWidth, min(560, geo.size.width * 0.55))
            let clampedPanelWidth = min(max(promptModePanelWidth, minPanelWidth), maxPanelWidth)
            let panelWidthBinding = Binding(
                get: { clampedPanelWidth },
                set: { promptModePanelWidth = $0 }
            )

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !board.isSmart {
                        CaptureBarView(currentBoardID: board.id)
                    }

                    if effectiveItems.isEmpty {
                        headerView.emptyState
                    } else {
                        headerView.suggestionsBar

                        BoardItemListView(
                            board: board,
                            sortedFilteredItems: sortedFilteredItems,
                            weekSections: weekSections,
                            canReorder: sortOption == .manual && !board.isSmart,
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

                if let selection = promptModeSelection {
                    ResizableTrailingDivider(
                        width: panelWidthBinding,
                        minWidth: minPanelWidth,
                        maxWidth: maxPanelWidth,
                        onCollapse: { promptModeSelection = nil }
                    ) { width in
                        LayoutSettings.setWidth(width, for: .boardPrompt)
                    }

                    BoardPromptModePanel(
                        label: selection.label,
                        prompt: selection.prompt,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                promptModeSelection = nil
                            }
                        },
                        onDialectic: { startDialectic(with: selection) },
                        onWrite: { startWriting(with: selection.prompt) }
                    )
                    .frame(width: panelWidthBinding.wrappedValue)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
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
            return unordered.sorted { $0.createdAt > $1.createdAt } + orderedItems
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
