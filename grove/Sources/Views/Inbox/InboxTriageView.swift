#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers

struct InboxTriageView: View {
    @Binding var selectedItem: ItemGraph?
    var openedItem: Binding<ItemGraph?>?
    var isEmbedded: Bool = false
    @Dependency(\.defaultDatabase) private var database
    @Fetch(Library.Request()) private var library = Library()
    /// Observed (not fetched on demand) so subscribing re-evaluates the cards
    /// and the "+ Follow" affordance disappears on its own.
    @FetchAll private var feedSources: [FeedSource]
    @State private var focusedIndex: Int = 0
    @State private var showQueuedSection = false
    @State private var showBoardPicker = false
    /// The picker files by ID and shows nothing of the item, so there's no copy
    /// here to go stale.
    @State private var itemIDToAssign: Item.ID?
    @State private var boardPickerSuggestedName: String = ""
    @State private var boardPickerRecommendedBoardID: UUID? = nil
    @State private var boardPickerAlternativeBoardIDs: [UUID] = []
    /// True when the picker was opened from "Change" on a filed confirmation:
    /// the pick replaces the item's board membership instead of appending.
    @State private var boardPickerReplacesMembership = false
    /// Transient "Filed to <board>" confirmation shown after a high-confidence
    /// auto-assign, so silent filing is always visible and reversible.
    @State private var filedConfirmation: FiledConfirmation? = nil
    @State private var filedConfirmationTask: Task<Void, Never>? = nil

    /// A board assignment made without asking, plus the item it applies to so
    /// "Change" can reopen the picker scoped to that item.
    private struct FiledConfirmation: Identifiable, Equatable {
        let id = UUID()
        let itemID: UUID
        let boardTitle: String
    }

    private var readLaterService: ReadLaterService {
        ReadLaterService()
    }

    private var boards: [BoardGraph] { library.boards }

    /// Personal captures awaiting triage. Feed items live in the
    /// Newsletters section, not here.
    private var inboxItems: [ItemGraph] {
        library.items
            .filter { $0.status == .inbox && !$0.isFeedSuggestion }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var queuedItems: [ItemGraph] {
        library.items
            .filter { $0.status == .queued && $0.isQueuedForReadLater }
            .sorted { ($0.readLaterUntil ?? .distantFuture) < ($1.readLaterUntil ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let filedConfirmation {
                filedConfirmationRow(filedConfirmation)
            }

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
        }
        .animation(.easeInOut(duration: 0.2), value: filedConfirmation)
        // Triage animates here rather than around its writes: the lists change
        // when the library next arrives, after any `withAnimation` has ended.
        .animation(.easeOut(duration: 0.25), value: inboxItems.isEmpty)
        .animation(.easeOut(duration: 0.25), value: queuedItems.map(\.id))
        .sheet(isPresented: $showBoardPicker) {
            if let itemID = itemIDToAssign {
                BoardPickerView(
                    boards: boards,
                    mode: .add,
                    suggestedName: boardPickerSuggestedName,
                    recommendedBoardID: boardPickerRecommendedBoardID,
                    alternativeBoardIDs: boardPickerAlternativeBoardIDs,
                    onSelect: { board in
                        database.attempt { db in
                            try Item.modify(itemID, in: db) {
                                BoardSuggestionMetadata.recordSelection(board.board, on: &$0)
                            }
                        }
                        let viewModel = ItemViewModel()
                        if boardPickerReplacesMembership {
                            viewModel.moveItemsToBoard([itemID], board: board.board)
                        } else {
                            viewModel.assignToBoard(itemID, board: board.board)
                        }
                        resetBoardPickerState()
                    },
                    onCreate: { title in
                        createAndAssignBoard(named: title, to: itemID)
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
            if !isPresented, itemIDToAssign != nil {
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
        .task(id: pendingDiscoveryDomain) {
            guard let domain = pendingDiscoveryDomain else { return }
            await FeedDiscoveryService.shared.discoverFeed(forDomain: domain)
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
                                suggestedBoards: suggestedBoards(for: item),
                                onKeep: { keepItem(item) },
                                onDrop: { dropItem(item) },
                                onQueue: { preset in queueItem(item, preset: preset) },
                                onConfirmTag: { tag in confirmTag(tag) },
                                onDismissTag: { tag in dismissTag(tag, from: item) },
                                onFileToBoard: { board in keepItem(item, filingTo: board) },
                                onMoreBoards: { presentBoardPicker(for: item) },
                                followableSite: followableSite(for: item),
                                onFollowSite: { followSite(for: item) }
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
                        suggestedBoards: suggestedBoards(for: item),
                        onKeep: { keepItem(item) },
                        onDrop: { dropItem(item) },
                        onQueue: { preset in queueItem(item, preset: preset) },
                        onConfirmTag: { tag in confirmTag(tag) },
                        onDismissTag: { tag in dismissTag(tag, from: item) },
                        onFileToBoard: { board in keepItem(item, filingTo: board) },
                        onMoreBoards: { presentBoardPicker(for: item) },
                        followableSite: followableSite(for: item),
                        onFollowSite: { followSite(for: item) }
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
            Text(queuedItems.isEmpty ? "Inbox clear" : queuedSummaryText)
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
            Text("Inbox clear")
                .font(.groveTitleLarge)
                .fontWeight(.semibold)
            if queuedItems.isEmpty {
                Text("Capture a link or note above.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                queuedDisclosure
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

    /// Keep an item. With no board, this is "keep unfiled" — it never raises a
    /// modal. Passing a board files it in the same gesture (the card's board
    /// chips). High-confidence auto-assign still fires for unfiled keeps, but
    /// now announces itself through the inline confirmation row.
    private func keepItem(_ item: ItemGraph, filingTo board: BoardGraph? = nil) {
        if item.isFeedSuggestion {
            recordSuggestionSignal(for: item, kept: true)
        }

        var autoAssigned: BoardGraph? = nil
        if board == nil, item.board == nil {
            // Auto-assign only when classification confidence is high.
            if let decision = BoardSuggestionMetadata.decision(from: item),
               let matchedBoard = autoAssignBoard(from: decision) {
                autoAssigned = matchedBoard
            } else if let suggestedName = item.metadata["suggestedBoard"],
                      let matchedBoard = boards.first(where: {
                          $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
                      }) {
                autoAssigned = matchedBoard
            }
        }

        let filedBoard = (board ?? autoAssigned)?.board
        database.attempt { db in
            try Item.modify(item.id, in: db) { row in
                if row.isFeedSuggestion {
                    // Kept suggestions become regular items; clear the flag so they
                    // leave the "From your subscriptions" grouping for good.
                    row.metadata["isSuggested"] = nil
                    row.metadata["suggestionDismissed"] = nil
                }

                row.status = .active
                row.updatedAt = .now

                if let filedBoard {
                    row.boardID = filedBoard.id
                    BoardSuggestionMetadata.recordSelection(filedBoard, on: &row)
                }
            }
            for tag in item.tags where tag.isAutoGenerated {
                try Item.removeTag(tag.id, fromItem: item.id, in: db)
            }
        }

        if board != nil {
            // Explicit one-gesture filing — no auto-assign, no confirmation.
            clearFiledConfirmation()
        } else if let autoAssigned {
            showFiledConfirmation(item: item, board: autoAssigned)
        }

        adjustFocusAfterRemoval(of: item.id)
    }

    /// Open the picker scoped to one item, seeded with its suggestion data.
    /// `replacingMembership` is the "Change" entry point: the pick corrects an
    /// assignment that already happened, so it must replace, not append.
    private func presentBoardPicker(for item: ItemGraph, replacingMembership: Bool = false) {
        let decision = BoardSuggestionMetadata.decision(from: item)
        boardPickerSuggestedName = decision?.suggestedName ?? (item.metadata["suggestedBoard"] ?? "")
        boardPickerRecommendedBoardID = decision?.recommendedBoardID
        boardPickerAlternativeBoardIDs = decision?.alternativeBoardIDs ?? []
        boardPickerReplacesMembership = replacingMembership
        itemIDToAssign = item.id
        showBoardPicker = true
    }

    /// One-click board chips for a card: recommended first, then alternates.
    private func suggestedBoards(for item: ItemGraph) -> [BoardGraph] {
        BoardRanking.suggestedBoards(for: item, from: boards)
    }

    // MARK: - Follow the Site

    /// Host of an item's source, normalized to match `FeedSource.domain`.
    /// Nil for anything that isn't a plain http(s) page — local files, notes,
    /// and custom schemes have no site to follow.
    private func followHost(for item: ItemGraph) -> String? {
        guard let urlString = item.sourceURL, !urlString.isEmpty,
              let url = resolvedSourceURL(from: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        let normalized = normalizedDomain(host)
        return normalized.isEmpty ? nil : normalized
    }

    private func feedSource(for item: ItemGraph) -> FeedSource? {
        guard let host = followHost(for: item) else { return nil }
        return feedSources.first { normalizedDomain($0.domain) == host }
    }

    /// Display domain for the card's "+ Follow" chip, or nil to show nothing.
    /// Only sites Grove already knows a feed for are offerable; a site with no
    /// FeedSource yet stays silent until on-demand discovery lands one.
    private func followableSite(for item: ItemGraph) -> String? {
        guard let host = followHost(for: item),
              let source = feedSource(for: item),
              !source.isUserSubscribed else { return nil }
        return host
    }

    private func followSite(for item: ItemGraph) {
        guard let source = feedSource(for: item), !source.isUserSubscribed else { return }
        FeedSubscriptionService.subscribe(source.id)
    }

    /// Domain of the focused card when Grove has no FeedSource for it yet.
    /// Drives a single `.task(id:)` rather than per-card work, so scrolling a
    /// long inbox doesn't fan out into a burst of homepage fetches.
    private var pendingDiscoveryDomain: String? {
        let items = inboxItems
        guard focusedIndex >= 0, focusedIndex < items.count else { return nil }
        let item = items[focusedIndex]
        // Newsletter issues already arrive from a subscription — there is
        // nothing left to follow.
        guard !item.isNewsletterIssue else { return nil }
        guard let host = followHost(for: item), feedSource(for: item) == nil else { return nil }
        return host
    }

    // MARK: - Auto-assign Confirmation

    private func showFiledConfirmation(item: ItemGraph, board: BoardGraph) {
        filedConfirmationTask?.cancel()
        filedConfirmation = FiledConfirmation(itemID: item.id, boardTitle: board.title)
        filedConfirmationTask = MainActorTaskScheduler.schedule(after: .seconds(6)) {
            withAnimation(.easeOut(duration: 0.2)) {
                filedConfirmation = nil
            }
        }
    }

    private func clearFiledConfirmation() {
        filedConfirmationTask?.cancel()
        filedConfirmationTask = nil
        filedConfirmation = nil
    }

    private func filedConfirmationRow(_ confirmation: FiledConfirmation) -> some View {
        HStack(spacing: Spacing.sm) {
            Text("Filed to \(confirmation.boardTitle)")
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Text("\u{2014}")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)

            Button("Change") {
                guard let item = library.item(confirmation.itemID) else { return }
                clearFiledConfirmation()
                presentBoardPicker(for: item, replacingMembership: true)
            }
            .buttonStyle(.plain)
            .font(.groveMeta)
            .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.textPrimary)
                .frame(width: 2)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .transition(.opacity)
    }

    private func dropItem(_ item: ItemGraph) {
        recordSuggestionSignal(for: item, kept: false)

        database.attempt { db in
            try Item.modify(item.id, in: db) {
                $0.status = .dismissed
                $0.updatedAt = .now
            }
        }

        adjustFocusAfterRemoval(of: item.id)
    }

    private func queueItem(_ item: ItemGraph, preset: ReadLaterPreset) {
        readLaterService.queue(item.id, for: preset)
        adjustFocusAfterRemoval(of: item.id)
    }

    private func autoAssignBoard(from decision: BoardSuggestionDecision) -> BoardGraph? {
        guard decision.mode == .existing else { return nil }
        guard decision.confidence >= 0.78 else { return nil }

        // Smart boards are rule-driven; membership must never be written into
        // them, so they are not auto-assign targets.
        if let recommendedBoardID = decision.recommendedBoardID,
           let recommended = boards.first(where: { $0.id == recommendedBoardID && !$0.isSmart }) {
            return recommended
        }

        return boards.first(where: {
            !$0.isSmart && $0.title.localizedCaseInsensitiveCompare(decision.suggestedName) == .orderedSame
        })
    }

    private func createAndAssignBoard(named rawTitle: String, to itemID: Item.ID) {
        let title = BoardSuggestionEngine.cleanedBoardName(rawTitle)
        guard !title.isEmpty else { return }

        let existingBoard = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        })?.board
        let board = existingBoard ?? Board(title: title)
        database.attempt { db in
            if existingBoard == nil {
                try Board.insert { board }.execute(db)
            }
            try Item.modify(itemID, in: db) {
                BoardSuggestionMetadata.recordSelection(board, on: &$0)
            }
        }
        ItemViewModel().assignToBoard(itemID, board: board)
    }

    private func resetBoardPickerState() {
        showBoardPicker = false
        itemIDToAssign = nil
        boardPickerSuggestedName = ""
        boardPickerRecommendedBoardID = nil
        boardPickerAlternativeBoardIDs = []
        boardPickerReplacesMembership = false
    }

    // MARK: - Tag Actions

    private func confirmTag(_ tag: Tag) {
        database.attempt { db in
            try Tag.modify(tag.id, in: db) { $0.isAutoGenerated = false }
        }
    }

    private func dismissTag(_ tag: Tag, from item: ItemGraph) {
        database.attempt { db in
            try Item.removeTag(tag.id, fromItem: item.id, in: db)
            try Item.modify(item.id, in: db) { $0.updatedAt = .now }
        }
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

    private func adjustFocusAfterRemoval(of itemID: Item.ID) {
        // After an item is removed, adjust focus so it stays in bounds. It's
        // still in `inboxItems` until the library next arrives, so leave it out.
        let items = inboxItems.filter { $0.id != itemID }
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

    /// Per-source keep/dismiss counters feeding the auto-throttle in
    /// FeedFetchService. No-op for non-suggested items.
    private func recordSuggestionSignal(for item: ItemGraph, kept: Bool) {
        guard item.isFeedSuggestion,
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
    private func readQueuedItemNow(_ item: ItemGraph) {
        readLaterService.restore(item.id)
        selectedItem = item
        openedItem?.wrappedValue = item
    }

    private func returnQueuedItemToInbox(_ item: ItemGraph) {
        readLaterService.restore(item.id)
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
        let captureService = CaptureService()
        _ = captureService.createVideoItem(filePath: path)
    }
}
