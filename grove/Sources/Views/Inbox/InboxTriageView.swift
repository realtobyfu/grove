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
    /// Embedded only: the focused item has room to set its cover beside its
    /// text. Today knows the column's width; this view does not.
    var focusCoverBeside: Bool = true
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var focusedIndex: Int = 0
    /// Embedded only: the id of the focused item, kept for the window. The
    /// index alone cannot say which item focus is on once the list changes
    /// around it (a capture arriving on top, a queued item coming back), and
    /// it is lost with the view each time Today gives way to the reader. The
    /// id is what brings focus back to the item that was just read.
    @SceneStorage("grove.inbox.focusedItemID") private var focusedItemKey: String?
    /// Embedded only: Today's inbox holds the keyboard, so the keys marked on
    /// its buttons work without a click first.
    @FocusState private var isTriageFocused: Bool
    @State private var showQueuedSection = false
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?
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
        ReadLaterService(modelContext: modelContext)
    }

    /// Personal captures awaiting triage. Feed items live in the
    /// Newsletters section, not here.
    private var inboxItems: [Item] {
        allItems.filter { $0.status == .inbox && !$0.isFeedSuggestion }
    }

    private var queuedItems: [Item] {
        allItems
            .filter { $0.status == .queued && $0.isQueuedForReadLater }
            .sorted { ($0.readLaterUntil ?? .distantFuture) < ($1.readLaterUntil ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmbedded {
                embeddedHeader
            }

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
        // Key presses reach a view only while it, or something inside it,
        // has focus. Embedded in Today the inbox is focusable for that
        // reason; the standalone list is left as it was. The section draws
        // no ring of its own — the focused item's ink rule is the mark —
        // while the controls inside keep theirs. `.edit` is the interaction
        // for a view that takes keyboard input: it accepts focus on a click
        // and from code whether or not system keyboard navigation is on.
        .focusEffectDisabled(false)
        .focusable(isEmbedded, interactions: .edit)
        .focused($isTriageFocused)
        .focusEffectDisabled()
        .sheet(isPresented: $showBoardPicker) {
            if let item = itemToAssign {
                BoardPickerView(
                    boards: boards,
                    mode: .add,
                    suggestedName: boardPickerSuggestedName,
                    recommendedBoardID: boardPickerRecommendedBoardID,
                    alternativeBoardIDs: boardPickerAlternativeBoardIDs,
                    onSelect: { board in
                        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
                        let viewModel = ItemViewModel(modelContext: modelContext)
                        if boardPickerReplacesMembership {
                            viewModel.moveItemsToBoard([item], board: board)
                        } else {
                            viewModel.assignToBoard(item, board: board)
                        }
                        resetBoardPickerState()
                    },
                    onCreate: { title in
                        createAndAssignBoard(named: title, to: item)
                        resetBoardPickerState()
                    }
                )
            }
        }
        .onKeyPress(phases: [.down]) { keyPress in
            handleTriageKeyPress(keyPress)
        }
        .onKeyPress(.return) {
            guard canHandleTriageShortcuts else { return .ignored }
            openFocusedItem()
            return .handled
        }
        // The arrows move focus as J and K do. They arrive with modifier
        // flags of their own, so they are matched by key, not through the
        // character handler above.
        .onKeyPress(.downArrow) {
            guard canHandleTriageShortcuts else { return .ignored }
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard canHandleTriageShortcuts else { return .ignored }
            moveFocus(by: -1)
            return .handled
        }
        .onChange(of: showBoardPicker) { _, isPresented in
            if !isPresented, itemToAssign != nil {
                resetBoardPickerState()
            }
        }
        .onChange(of: inboxItems.map(\.id)) { _, ids in
            if isEmbedded {
                anchorFocus(in: ids)
            }
        }
        .onAppear {
            restoreDueQueuedItems()
            if isEmbedded {
                anchorFocus(in: inboxItems.map(\.id))
            }
        }
        .task {
            // Take the keyboard on arrival, unless the reader is typing
            // somewhere (the search or capture overlay).
            if isEmbedded, canHandleTriageShortcuts {
                isTriageFocused = true
            }
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
                VStack(spacing: Spacing.sm) {
                    if !queuedItems.isEmpty {
                        queuedDisclosure
                    }

                    LazyVStack(spacing: Spacing.sm) {
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
                                onMoreBoards: { presentBoardPicker(for: item) }
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

    // MARK: - Embedded Inbox (Today)

    /// The section's label, with the focused item's place in the inbox.
    private var embeddedHeader: some View {
        let items = inboxItems
        let count = items.count
        let position = InboxFocus.clampedIndex(currentFocusIndex(in: items), count: count) + 1
        return TodaySectionHeader(
            title: "Inbox",
            badge: count == 0 ? nil : "\(position) of \(count)"
        )
    }

    /// One item at a time: the focused item at full size, and every other
    /// inbox item as a one-line row under it, numbered by its place in the
    /// inbox. Clicking a row moves focus to it.
    @ViewBuilder
    private var embeddedInboxList: some View {
        let items = inboxItems
        let index = InboxFocus.clampedIndex(currentFocusIndex(in: items), count: items.count)

        VStack(alignment: .leading, spacing: 0) {
            if !queuedItems.isEmpty {
                queuedDisclosure
                    .padding(.bottom, Spacing.sm)
            }

            if items.indices.contains(index) {
                let focused = items[index]

                InboxFocusCard(
                    item: focused,
                    suggestedBoards: suggestedBoards(for: focused),
                    coverBeside: focusCoverBeside,
                    onKeep: { keepItem(focused) },
                    onDrop: { dropItem(focused) },
                    onQueue: { preset in queueItem(focused, preset: preset) },
                    onOpen: { openInReader(focused) },
                    onConfirmTag: { tag in confirmTag(tag) },
                    onDismissTag: { tag in dismissTag(tag, from: focused) },
                    onFileToBoard: { board in keepItem(focused, filingTo: board) },
                    onMoreBoards: { presentBoardPicker(for: focused) }
                )
                .id(focused.id)
                .transition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture {
                    // A click on the card itself selects the item, which is
                    // what brings up Info for it — as a click on any card
                    // in the window does.
                    isTriageFocused = true
                    selectedItem = focused
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    if offset != index {
                        TodayRow(
                            lead: "\(offset + 1)",
                            leadSlot: "\(items.count)",
                            title: item.title,
                            note: InboxFocus.sourceLabel(for: item),
                            showsRule: offset != InboxFocus.lastRowIndex(count: items.count, focused: index),
                            action: {
                                isTriageFocused = true
                                focus(index: offset, in: items)
                            }
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items.map(\.id))
    }

    // MARK: - Empty State

    private var embeddedEmptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroveEmptyState(
                title: "Inbox clear",
                detail: queuedItems.isEmpty ? "Capture a link or note above." : queuedSummaryText
            )

            if !queuedItems.isEmpty {
                queuedDisclosure
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
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
        let index = currentFocusIndex(in: items)
        guard index >= 0, index < items.count else { return }
        let item = items[index]

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
    private func keepItem(_ item: Item, filingTo board: Board? = nil) {
        if item.isFeedSuggestion {
            // Kept suggestions become regular items; clear the flag so they
            // leave the "From your subscriptions" grouping for good.
            item.isFeedSuggestion = false
            item.isSuggestionDismissed = false
        }

        item.status = .active
        item.updatedAt = .now
        item.tags.removeAll { $0.isAutoGenerated }

        if let board {
            // Explicit one-gesture filing — no auto-assign, no confirmation.
            BoardSuggestionMetadata.clearPendingSuggestion(on: item)
            ItemViewModel(modelContext: modelContext).assignToBoard(item, board: board)
            clearFiledConfirmation()
        } else if item.boards.isEmpty {
            // Auto-assign only when classification confidence is high.
            var autoAssigned: Board? = nil
            if let decision = BoardSuggestionMetadata.decision(from: item),
               let matchedBoard = autoAssignBoard(from: decision) {
                autoAssigned = matchedBoard
            } else if let suggestedName = item.suggestedBoard,
                      let matchedBoard = boards.first(where: {
                          $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
                      }) {
                autoAssigned = matchedBoard
            }

            if let autoAssigned {
                item.boards.append(autoAssigned)
                BoardSuggestionMetadata.clearPendingSuggestion(on: item)
                showFiledConfirmation(item: item, board: autoAssigned)
            }
        }

        try? modelContext.save()

        adjustFocusAfterRemoval(of: item)
    }

    /// Open the picker scoped to one item, seeded with its suggestion data.
    /// `replacingMembership` is the "Change" entry point: the pick corrects an
    /// assignment that already happened, so it must replace, not append.
    private func presentBoardPicker(for item: Item, replacingMembership: Bool = false) {
        let decision = BoardSuggestionMetadata.decision(from: item)
        boardPickerSuggestedName = decision?.suggestedName ?? (item.suggestedBoard ?? "")
        boardPickerRecommendedBoardID = decision?.recommendedBoardID
        boardPickerAlternativeBoardIDs = decision?.alternativeBoardIDs ?? []
        boardPickerReplacesMembership = replacingMembership
        itemToAssign = item
        showBoardPicker = true
    }

    /// One-click board chips for a card: recommended first, then alternates.
    private func suggestedBoards(for item: Item) -> [Board] {
        BoardRanking.suggestedBoards(for: item, from: boards)
    }

    // MARK: - Auto-assign Confirmation

    private func showFiledConfirmation(item: Item, board: Board) {
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
                guard let item = allItems.first(where: { $0.id == confirmation.itemID }) else { return }
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
        // The standalone list is inset; in Today the row sits on the
        // column's own edges, between the section label and the item.
        .padding(.horizontal, isEmbedded ? 0 : Spacing.lg)
        .padding(.top, isEmbedded ? 0 : Spacing.sm)
        .padding(.bottom, isEmbedded ? Spacing.sm : 0)
        .transition(.opacity)
    }

    private func dropItem(_ item: Item) {
        withAnimation(.easeOut(duration: 0.3)) {
            item.status = .dismissed
            item.updatedAt = .now
            try? modelContext.save()
        }

        adjustFocusAfterRemoval(of: item)
    }

    private func queueItem(_ item: Item, preset: ReadLaterPreset) {
        withAnimation(.easeOut(duration: 0.25)) {
            readLaterService.queue(item, for: preset)
        }
        adjustFocusAfterRemoval(of: item)
    }

    private func autoAssignBoard(from decision: BoardSuggestionDecision) -> Board? {
        guard decision.mode == .existing else { return nil }
        guard decision.confidence >= 0.78 else { return nil }

        if let recommendedBoardID = decision.recommendedBoardID,
           let recommended = boards.first(where: { $0.id == recommendedBoardID }) {
            return recommended
        }

        return boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(decision.suggestedName) == .orderedSame
        })
    }

    private func createAndAssignBoard(named rawTitle: String, to item: Item) {
        let title = BoardSuggestionEngine.cleanedBoardName(rawTitle)
        guard !title.isEmpty else { return }

        if let existingBoard = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            BoardSuggestionMetadata.clearPendingSuggestion(on: item)
            let viewModel = ItemViewModel(modelContext: modelContext)
            viewModel.assignToBoard(item, board: existingBoard)
        } else {
            let board = Board(title: title)
            modelContext.insert(board)
            BoardSuggestionMetadata.clearPendingSuggestion(on: item)
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
        boardPickerReplacesMembership = false
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

    /// The row in focus.
    ///
    /// The standalone list keeps it as an index. Today reads it from the
    /// remembered item instead, so the item on screen, the count beside the
    /// label and the keys all agree from the first frame — including the
    /// frame Today is rebuilt in on the way back from the reader, before
    /// `anchorFocus` has brought the stored index up to date.
    private func currentFocusIndex(in items: [Item]) -> Int {
        guard isEmbedded else { return focusedIndex }
        return InboxFocus.index(
            following: focusedItemKey.flatMap { UUID(uuidString: $0) },
            previousIndex: focusedIndex,
            in: items.map(\.id)
        )
    }

    private func moveFocus(by offset: Int) {
        let items = inboxItems
        guard !items.isEmpty else { return }
        let newIndex = max(0, min(items.count - 1, currentFocusIndex(in: items) + offset))
        focus(index: newIndex, in: items)
    }

    /// Puts focus on one row.
    ///
    /// The standalone list selects whatever is focused (its own
    /// `onChange(of: focusedIndex)`). Today does not: a selection brings up
    /// the window's Info page, and stepping through the inbox must not open
    /// it. If the reader has asked for Info on the item focus is leaving,
    /// the selection moves on with the focus; otherwise it is left alone.
    private func focus(index: Int, in items: [Item]) {
        guard items.indices.contains(index) else { return }
        let previousIndex = currentFocusIndex(in: items)
        let previous = items.indices.contains(previousIndex) ? items[previousIndex] : nil
        focusedIndex = index
        guard isEmbedded else { return }
        focusedItemKey = items[index].id.uuidString
        if let selected = selectedItem, selected.id == previous?.id {
            selectedItem = items[index]
        }
    }

    /// Keeps focus on the same item when the inbox changes around it, and
    /// returns it to that item when Today comes back from the reader.
    private func anchorFocus(in ids: [UUID]) {
        let index = InboxFocus.index(
            following: focusedItemKey.flatMap { UUID(uuidString: $0) },
            previousIndex: focusedIndex,
            in: ids
        )
        let key = ids.indices.contains(index) ? ids[index].uuidString : nil
        if focusedIndex != index {
            focusedIndex = index
        }
        if focusedItemKey != key {
            focusedItemKey = key
        }
    }

    private func openFocusedItem() {
        let items = inboxItems
        let index = currentFocusIndex(in: items)
        guard index >= 0, index < items.count else { return }
        openInReader(items[index])
    }

    /// Opens an item in the reader, selected and opened together like every
    /// other route into it, so Info and Export describe what is on screen.
    private func openInReader(_ item: Item) {
        selectedItem = item
        openedItem?.wrappedValue = item
    }

    private func adjustFocusAfterRemoval(of removed: Item) {
        // After an item is removed, adjust focus so it stays in bounds
        let items = inboxItems
        let next: Item?
        if items.isEmpty {
            focusedIndex = 0
            next = nil
        } else {
            focusedIndex = min(focusedIndex, items.count - 1)
            next = items[focusedIndex]
        }

        guard isEmbedded else {
            selectedItem = next
            return
        }

        // Today: the item that slid into place is in focus, and stays so if
        // the list reorders. The selection follows only if Info was already
        // up for the item just triaged (see `focus(index:in:)`).
        focusedItemKey = next?.id.uuidString
        if selectedItem?.id == removed.id {
            selectedItem = next
        }
        // A click on a button does not move keyboard focus here by itself.
        isTriageFocused = true
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
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
}

// MARK: - Inbox Focus

/// Where focus sits in the inbox, and what Today's one-line rows say. Pure,
/// so the rules can be tested without a view.
enum InboxFocus {
    /// An index that is always safe to read with: within `0..<count`, or 0
    /// for an empty inbox.
    static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    /// The row focus belongs on after the inbox changes.
    ///
    /// Focus follows the item, not the row number: a capture arriving above
    /// the focused item pushes it down a place and focus goes with it. When
    /// the focused item has left the inbox, the item that slid into its
    /// place takes over.
    static func index(following focusedID: UUID?, previousIndex: Int, in ids: [UUID]) -> Int {
        if let focusedID, let index = ids.firstIndex(of: focusedID) {
            return index
        }
        return clampedIndex(previousIndex, count: ids.count)
    }

    /// The last of the one-line rows — every item but the focused one — so
    /// the list can end without a rule under it. Nil when there are no rows.
    static func lastRowIndex(count: Int, focused: Int) -> Int? {
        guard count > 1 else { return nil }
        return focused == count - 1 ? count - 2 : count - 1
    }

    /// What a row says about where its item came from: the source's domain,
    /// or the kind of thing it is when it has no source.
    static func sourceLabel(for item: Item) -> String {
        if let url = item.sourceURL, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return domainFrom(url)
        }
        return item.type.displayName
    }
}
