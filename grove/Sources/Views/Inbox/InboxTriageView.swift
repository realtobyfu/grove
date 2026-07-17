#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
    @State private var showQueuedSection = false
    @State private var showSuggestedSection = false
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?
    @State private var boardPickerSuggestedName: String = ""
    @State private var boardPickerRecommendedBoardID: UUID? = nil
    @State private var boardPickerAlternativeBoardIDs: [UUID] = []

    private var readLaterService: ReadLaterService {
        ReadLaterService(modelContext: modelContext)
    }

    /// Personal captures awaiting triage. Feed suggestions are grouped
    /// separately so the user's own material stays visually primary.
    private var inboxItems: [Item] {
        allItems.filter { $0.status == .inbox && !isSuggested($0) }
    }

    /// Items created by the feed pipeline (metadata isSuggested == "true"),
    /// excluding expired/dismissed suggestions.
    private var suggestedItems: [Item] {
        allItems.filter {
            $0.status == .inbox
                && isSuggested($0)
                && $0.metadata["suggestionDismissed"] != "true"
        }
    }

    private func isSuggested(_ item: Item) -> Bool {
        item.metadata["isSuggested"] == "true"
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
                        BoardSuggestionMetadata.recordSelection(board, on: item)
                        let viewModel = ItemViewModel(modelContext: modelContext)
                        viewModel.assignToBoard(item, board: board)
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
        .onKeyPress(phases: [.down]) { keyPress in
            handleTriageKeyPress(keyPress)
        }
        .onKeyPress(.return) {
            guard canHandleTriageShortcuts else { return .ignored }
            openFocusedItem()
            return .handled
        }
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
                        queuedDisclosure
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

                    if !suggestedItems.isEmpty {
                        suggestedDisclosure
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
                queuedDisclosure
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

            if !suggestedItems.isEmpty {
                suggestedDisclosure
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
            if queuedItems.isEmpty {
                Text("Nice work! No items waiting for triage.\nCapture a link or note above to get started.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                queuedDisclosure
                    .frame(maxWidth: 420)
            }

            if !suggestedItems.isEmpty {
                suggestedDisclosure
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Keyboard Handlers

    private var canHandleTriageShortcuts: Bool {
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

    private func handleTriageKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard canHandleTriageShortcuts else { return .ignored }
        guard keyPress.modifiers.isEmpty else { return .ignored }

        switch keyPress.characters.lowercased() {
        case "j":
            moveFocus(by: 1)
            return .handled
        case "k":
            moveFocus(by: -1)
            return .handled
        case "1":
            performAction(.keep)
            return .handled
        case "2":
            performAction(.drop)
            return .handled
        case "3":
            performAction(.later)
            return .handled
        default:
            return .ignored
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
        if isSuggested(item) {
            recordSuggestionSignal(for: item, kept: true)
            // Kept suggestions become regular items; clear the flag so they
            // leave the "From your subscriptions" grouping for good.
            item.metadata["isSuggested"] = nil
            item.metadata["suggestionDismissed"] = nil
        }

        item.status = .active
        item.updatedAt = .now
        item.tags.removeAll { $0.isAutoGenerated }

        // Auto-assign only when classification confidence is high
        if item.boards.isEmpty,
           let decision = BoardSuggestionMetadata.decision(from: item),
           let matchedBoard = autoAssignBoard(from: decision) {
            item.boards.append(matchedBoard)
            BoardSuggestionMetadata.recordSelection(matchedBoard, on: item)
        } else if item.boards.isEmpty,
                  let suggestedName = item.metadata["suggestedBoard"],
                  let matchedBoard = boards.first(where: { $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame }) {
            item.boards.append(matchedBoard)
            BoardSuggestionMetadata.recordSelection(matchedBoard, on: item)
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
        recordSuggestionSignal(for: item, kept: false)

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
            BoardSuggestionMetadata.recordSelection(existingBoard, on: item)
            let viewModel = ItemViewModel(modelContext: modelContext)
            viewModel.assignToBoard(item, board: existingBoard)
        } else {
            let board = Board(title: title)
            modelContext.insert(board)
            BoardSuggestionMetadata.recordSelection(board, on: item)
            let viewModel = ItemViewModel(modelContext: modelContext)
            viewModel.assignToBoard(item, board: board)
        }
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

    private func openFocusedItem() {
        let items = inboxItems
        guard focusedIndex >= 0, focusedIndex < items.count else { return }
        openedItem?.wrappedValue = items[focusedIndex]
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

    /// Collapsible "Queued for later (N)" row that expands the reading queue inline.
    /// Shared chrome for the inbox's collapsible sections (queued + suggestions)
    /// so their styling and animation stay identical.
    @ViewBuilder
    private func disclosureCard<Content: View>(
        systemImage: String,
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: systemImage)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                    Text(title)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(isExpanded.wrappedValue ? .degrees(90) : .zero)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                Divider()
                content()
            }
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }

    private var queuedDisclosure: some View {
        disclosureCard(
            systemImage: "clock.badge",
            title: "Queued for later (\(queuedItems.count))",
            isExpanded: $showQueuedSection
        ) {
            ReadingQueueView(
                items: queuedItems,
                onReadNow: readQueuedItemNow,
                onReturnToInbox: returnQueuedItemToInbox
            )
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - Suggested From Subscriptions

    /// Collapsible "From your subscriptions (N)" row, styled like the queued
    /// disclosure. Keeps feed suggestions quieter than personal captures.
    private var suggestedDisclosure: some View {
        disclosureCard(
            systemImage: "newspaper",
            title: "From your subscriptions (\(suggestedItems.count))",
            isExpanded: $showSuggestedSection
        ) {
            LazyVStack(spacing: 8) {
                    ForEach(suggestedItems) { item in
                        InboxCard(
                            item: item,
                            isSelected: false,
                            onKeep: { keepItem(item) },
                            onDrop: { dropItem(item) },
                            onQueue: { preset in queueItem(item, preset: preset) },
                            onConfirmTag: { tag in confirmTag(tag) },
                            onDismissTag: { tag in dismissTag(tag, from: item) }
                        )
                        .contextMenu {
                            Button {
                                fewerLikeThis(item)
                            } label: {
                                Label("Fewer like this", systemImage: "hand.thumbsdown")
                            }
                            Button {
                                unsubscribe(from: item)
                            } label: {
                                Label(
                                    "Unsubscribe from \(feedDisplayName(for: item))",
                                    systemImage: "bell.slash"
                                )
                            }
                        }
                        .onTapGesture {
                            selectedItem = item
                        }
                    }
                }
                .padding(Spacing.sm)
                .animation(.easeInOut(duration: 0.25), value: suggestedItems.map(\.id))
            }
        }

    private func feedSource(for item: Item) -> FeedSource? {
        guard let idString = item.metadata["feedSourceID"],
              let id = UUID(uuidString: idString) else { return nil }
        let descriptor = FetchDescriptor<FeedSource>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func feedDisplayName(for item: Item) -> String {
        if let source = feedSource(for: item) {
            return source.title ?? source.domain
        }
        return item.metadata["feedSourceDomain"] ?? "this feed"
    }

    /// Disables the item's feed source so it stops producing suggestions and
    /// clears the subscription flag (returns it to "Suggested from your library").
    private func unsubscribe(from item: Item) {
        guard let source = feedSource(for: item) else { return }
        source.isEnabled = false
        source.isUserSubscribed = false
        try? modelContext.save()
    }

    /// Records a dismissal signal for the item's source and drops the item.
    /// Sources with many dismissals and no keeps get throttled by the fetcher.
    private func fewerLikeThis(_ item: Item) {
        recordSuggestionSignal(for: item, kept: false)
        withAnimation(.easeOut(duration: 0.3)) {
            item.status = .dismissed
            item.metadata["suggestionDismissed"] = "true"
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    /// Per-source keep/dismiss counters feeding the auto-throttle in
    /// FeedFetchService. No-op for non-suggested items.
    private func recordSuggestionSignal(for item: Item, kept: Bool) {
        guard isSuggested(item),
              let idString = item.metadata["feedSourceID"],
              let id = UUID(uuidString: idString) else { return }
        if kept {
            FeedPreferencesStore.recordKeep(sourceID: id)
        } else {
            FeedPreferencesStore.recordDismissal(sourceID: id)
        }
    }

    /// Restore a queued item to the inbox and open it for reading,
    /// using the same open mechanism as Return on a focused inbox card.
    private func readQueuedItemNow(_ item: Item) {
        readLaterService.restore(item)
        selectedItem = item
        openedItem?.wrappedValue = item
    }

    private func returnQueuedItemToInbox(_ item: Item) {
        withAnimation(.easeInOut(duration: 0.2)) {
            readLaterService.restore(item)
        }
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
