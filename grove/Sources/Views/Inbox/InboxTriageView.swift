import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InboxTriageView: View {
    @Binding var selectedItem: Item?
    var openedItem: Binding<Item?>?
    var isEmbedded: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var focusedIndex: Int = 0
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?
    @State private var boardPickerSuggestedName: String = ""
    @State private var boardPickerRecommendedBoardID: UUID? = nil
    @State private var boardPickerAlternativeBoardIDs: [UUID] = []

    private var readLaterService: ReadLaterService {
        ReadLaterService(modelContext: modelContext)
    }

    private var inboxItems: [Item] {
        allItems.filter { $0.status == .inbox }
    }

    private var queuedItems: [Item] {
        allItems
            .filter { $0.status == .queued && $0.isQueuedForReadLater }
            .sorted { ($0.readLaterUntil ?? .distantFuture) < ($1.readLaterUntil ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if inboxItems.isEmpty {
                if isEmbedded {
                    embeddedEmptyState
                } else {
                    emptyState
                }
            } else {
                if isEmbedded {
                    embeddedInboxList
                } else {
                    inboxList
                }
            }
        }
        .sheet(isPresented: $showBoardPicker) {
            if let item = itemToAssign {
                SmartBoardPickerSheet(
                    boards: boards,
                    suggestedName: boardPickerSuggestedName,
                    recommendedBoardID: boardPickerRecommendedBoardID,
                    prioritizedBoardIDs: boardPickerAlternativeBoardIDs,
                    onSelectBoard: { board in
                        let viewModel = ItemViewModel(modelContext: modelContext)
                        viewModel.assignToBoard(item, board: board)
                        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
                        try? modelContext.save()
                        resetBoardPickerState()
                    },
                    onCreateBoard: { title in
                        createAndAssignBoard(named: title, to: item)
                        resetBoardPickerState()
                    }
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleVideoDrop(providers: providers)
        }
        .background(keyboardHandlers)
        .onChange(of: showBoardPicker) { _, isPresented in
            if !isPresented, itemToAssign != nil {
                resetBoardPickerState()
            }
        }
        .onAppear {
            restoreDueQueuedItems()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                restoreDueQueuedItems()
            }
        }
    }

    // MARK: - Inbox List

    private var inboxList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if !queuedItems.isEmpty {
                        queuedSummaryBanner
                    }

                    LazyVStack(spacing: 8) {
                        ForEach(Array(inboxItems.enumerated()), id: \.element.id) { index, item in
                            InboxCard(
                                item: item,
                                isSelected: index == focusedIndex,
                                onKeep: { keepItem(item) },
                                onDrop: { dropItem(item) },
                                onQueue: { preset in queueItem(item, preset: preset) },
                                onConfirmTag: { tag in confirmTag(tag) },
                                onDismissTag: { tag in dismissTag(tag, from: item) }
                            )
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            ))
                            .onTapGesture {
                                focusedIndex = index
                                selectedItem = item
                            }
                        }
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.25), value: inboxItems.map(\.id))
            }
            .onChange(of: focusedIndex) { _, newIndex in
                let items = inboxItems
                guard newIndex >= 0, newIndex < items.count else { return }
                selectedItem = items[newIndex]
                withAnimation {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
            .onAppear {
                if !inboxItems.isEmpty {
                    focusedIndex = 0
                    selectedItem = inboxItems.first
                }
            }
        }
    }

    // MARK: - Embedded Inbox List

    private var embeddedInboxList: some View {
        let visibleItems = Array(inboxItems.prefix(8))
        return VStack(spacing: 8) {
            if !queuedItems.isEmpty {
                queuedSummaryBanner
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300, maximum: 600), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    InboxCard(
                        item: item,
                        isSelected: index == focusedIndex,
                        onKeep: { keepItem(item) },
                        onDrop: { dropItem(item) },
                        onQueue: { preset in queueItem(item, preset: preset) },
                        onConfirmTag: { tag in confirmTag(tag) },
                        onDismissTag: { tag in dismissTag(tag, from: item) }
                    )
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .move(edge: .trailing))
                    ))
                    .onTapGesture {
                        focusedIndex = index
                        selectedItem = item
                    }
                }
            }

            if inboxItems.count > 8 {
                Button {
                    NotificationCenter.default.post(name: .groveGoToHome, object: nil)
                } label: {
                    Text("Show all \(inboxItems.count) items")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.25), value: inboxItems.map(\.id))
    }

    // MARK: - Empty State

    private var embeddedEmptyState: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: queuedItems.isEmpty ? "checkmark.circle" : "clock.badge")
                .font(.groveBody)
                .foregroundStyle(Color.textTertiary)
            Text(queuedItems.isEmpty ? "All caught up — inbox is clear." : queuedSummaryText)
                .font(.groveBody)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: queuedItems.isEmpty ? "tray" : "clock.badge")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text(queuedItems.isEmpty ? "Inbox Clear" : "Inbox Clear For Now")
                .font(.groveTitleLarge)
                .fontWeight(.semibold)
            Text(queuedItems.isEmpty
                ? "Nice work! No items waiting for triage.\nCapture something with ⌘+Shift+K to get started."
                : queuedSummaryText
            )
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Handlers

    private var keyboardHandlers: some View {
        Group {
            // J — move down
            Button("") { moveFocus(by: 1) }
                .keyboardShortcut("j", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // K — move up
            Button("") { moveFocus(by: -1) }
                .keyboardShortcut("k", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // 1 — Keep
            Button("") { performAction(.keep) }
                .keyboardShortcut("1", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // 2 — Drop
            Button("") { performAction(.drop) }
                .keyboardShortcut("2", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // 3 — Queue until tomorrow morning
            Button("") { performAction(.later) }
                .keyboardShortcut("3", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // Enter — Open selected item
            Button("") {
                let items = inboxItems
                guard focusedIndex >= 0, focusedIndex < items.count else { return }
                openedItem?.wrappedValue = items[focusedIndex]
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    // MARK: - Actions

    private enum TriageAction {
        case keep, later, drop
    }

    private func performAction(_ action: TriageAction) {
        let items = inboxItems
        guard focusedIndex >= 0, focusedIndex < items.count else { return }
        let item = items[focusedIndex]

        switch action {
        case .keep:
            keepItem(item)
        case .later:
            queueItem(item, preset: .tomorrowMorning)
        case .drop:
            dropItem(item)
        }
    }

    private func keepItem(_ item: Item) {
        item.status = .active
        item.updatedAt = .now
        item.tags.removeAll { $0.isAutoGenerated }

        // Auto-assign only when classification confidence is high
        if item.boards.isEmpty,
           let decision = BoardSuggestionMetadata.decision(from: item),
           let matchedBoard = autoAssignBoard(from: decision) {
            item.boards.append(matchedBoard)
            BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        } else if item.boards.isEmpty,
                  let suggestedName = item.metadata["suggestedBoard"],
                  let matchedBoard = boards.first(where: { $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame }) {
            item.boards.append(matchedBoard)
            BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        }

        try? modelContext.save()

        // Only show board picker if the item still has no board assigned
        if item.boards.isEmpty {
            let decision = BoardSuggestionMetadata.decision(from: item)
            boardPickerSuggestedName = decision?.suggestedName ?? (item.metadata["suggestedBoard"] ?? "")
            boardPickerRecommendedBoardID = decision?.recommendedBoardID
            boardPickerAlternativeBoardIDs = decision?.alternativeBoardIDs ?? []
            itemToAssign = item
            showBoardPicker = true
        }

        adjustFocusAfterRemoval()
    }

    private func dropItem(_ item: Item) {
        withAnimation(.easeOut(duration: 0.3)) {
            item.status = .dismissed
            item.updatedAt = .now
            try? modelContext.save()
        }

        adjustFocusAfterRemoval()
    }

    private func queueItem(_ item: Item, preset: ReadLaterPreset) {
        withAnimation(.easeOut(duration: 0.25)) {
            readLaterService.queue(item, for: preset)
        }
        adjustFocusAfterRemoval()
    }

    private func autoAssignBoard(from decision: BoardSuggestionDecision) -> Board? {
        guard decision.mode == .existing else { return nil }
        guard decision.confidence >= 0.78 else { return nil }

        if let recommendedBoardID = decision.recommendedBoardID,
           let recommended = boards.first(where: { $0.id == recommendedBoardID }) {
            return recommended
        }

        return boards.first(where: { $0.title.localizedCaseInsensitiveCompare(decision.suggestedName) == .orderedSame })
    }

    private func createAndAssignBoard(named rawTitle: String, to item: Item) {
        let title = BoardSuggestionEngine.cleanedBoardName(rawTitle)
        guard !title.isEmpty else { return }

        if let existingBoard = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            if !item.boards.contains(where: { $0.id == existingBoard.id }) {
                item.boards.append(existingBoard)
            }
        } else {
            let board = Board(title: title)
            modelContext.insert(board)
            item.boards.append(board)
        }

        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        try? modelContext.save()
    }

    private func resetBoardPickerState() {
        showBoardPicker = false
        itemToAssign = nil
        boardPickerSuggestedName = ""
        boardPickerRecommendedBoardID = nil
        boardPickerAlternativeBoardIDs = []
    }

    // MARK: - Tag Actions

    private func confirmTag(_ tag: Tag) {
        tag.isAutoGenerated = false
        try? modelContext.save()
    }

    private func dismissTag(_ tag: Tag, from item: Item) {
        item.tags.removeAll { $0.id == tag.id }
        item.updatedAt = .now
        try? modelContext.save()
    }

    private func moveFocus(by offset: Int) {
        let items = inboxItems
        guard !items.isEmpty else { return }
        let newIndex = max(0, min(items.count - 1, focusedIndex + offset))
        focusedIndex = newIndex
    }

    private func adjustFocusAfterRemoval() {
        // After an item is removed, adjust focus so it stays in bounds
        let items = inboxItems
        if items.isEmpty {
            focusedIndex = 0
            selectedItem = nil
        } else {
            focusedIndex = min(focusedIndex, items.count - 1)
            selectedItem = items[focusedIndex]
        }
    }

    private var queuedSummaryText: String {
        let count = queuedItems.count
        guard count > 0 else { return "" }
        if let next = queuedItems.first?.readLaterUntil {
            return "\(count) queued for later, next returns \(next.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(count) queued for later"
    }

    private var queuedSummaryBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "clock.badge")
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
            Text(queuedSummaryText)
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }

    private func restoreDueQueuedItems() {
        _ = readLaterService.restoreDueItems()
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
                    importDroppedVideo(at: path)
                }
            }
            handled = true
        }
        return handled
    }

    @MainActor
    private func importDroppedVideo(at path: String) {
        let captureService = CaptureService(modelContext: modelContext)
        _ = captureService.createVideoItem(filePath: path)
    }
}
