import SwiftUI
import SwiftData
import Combine

// MARK: - Library Sort Option

/// User-selectable sort order for the library list.
/// Search-result ranking (fuzzy score) is unaffected.
///
/// Persisted by raw value through `@AppStorage("librarySortOption")`. A stored
/// value with no matching case (e.g. "depth", from the removed Depth sort)
/// fails to decode and `@AppStorage` falls back to the default sort.
enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case dateAdded
    case titleAZ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyUpdated: "Recently updated"
        case .dateAdded: "Date added"
        case .titleAZ: "Title A\u{2013}Z"
        }
    }

    func sorted(_ items: [Item]) -> [Item] {
        switch self {
        case .recentlyUpdated:
            items.sorted { $0.updatedAt > $1.updatedAt }
        case .dateAdded:
            items.sorted { $0.createdAt > $1.createdAt }
        case .titleAZ:
            items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    /// The two date sorts read as a chronicle and are set under month
    /// headings. Title A–Z is one alphabetical run with no headings.
    var groupsByMonth: Bool {
        self != .titleAZ
    }

    /// The date an index row shows, and the one its month heading is taken
    /// from: the date the list is sorted by, or the last update for A–Z.
    func date(for item: Item) -> Date {
        switch self {
        case .dateAdded: item.createdAt
        case .recentlyUpdated, .titleAZ: item.updatedAt
        }
    }
}

// MARK: - Search Limits

extension SearchResultLimits {
    /// The Library's limits: it is an index, so every title, text, tag and
    /// board match inside the scope its filters show is listed. "Related in
    /// meaning" keeps the overlay's limit; it is a suggestion, not a match.
    static let library = SearchResultLimits(
        items: .max,
        reflections: .max,
        tags: .max,
        boards: .max,
        related: SearchResultLimits.overlay.related
    )
}

// MARK: - LibraryView

/// The Library: the index of everything saved, and the place you search it.
///
/// With nothing in the find field the page lists every item one to a line,
/// under month headings for the two date sorts. With a query it lists what
/// `SearchViewModel` finds, grouped by where the match is (`LibraryFind`).
/// Boards act as filter chips on both.
///
/// The window takes this view down while an item is open, so the query and
/// the filter chips are kept per scene (`@SceneStorage`) and are still there
/// when the reader is closed. The sort order is kept for the app
/// (`@AppStorage`).
struct LibraryView: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]

    @SceneStorage("library.findQuery") private var searchQuery: String = ""
    /// The search behind the find field: the same view model the search
    /// overlay drives, scoped to the items the filters show and with the
    /// Library's raised limits. Built when the page appears.
    @State private var searchViewModel: SearchViewModel?
    /// The board chip, as a UUID string ("" for All): scene storage holds
    /// strings, not UUIDs. Read through `selectedBoardID`.
    @SceneStorage("library.boardID") private var storedBoardID: String = ""
    @SceneStorage("library.showingArchived") private var showingArchived: Bool = false
    @State private var itemToDelete: Item?
    /// The row Down and Up have moved to from the find field.
    @State private var cursor = LibraryFindCursor()

    @AppStorage("librarySortOption") private var sortOption: LibrarySortOption = .recentlyUpdated

    // Multi-select state
    @State private var isMultiSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBoardPicker = false
    @State private var showBulkDeleteConfirm = false

    // MARK: - Computed

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True while there is a query: the list shows find results, not the index.
    private var isFinding: Bool {
        !trimmedQuery.isEmpty
    }

    /// True from a keystroke until the results for it have landed.
    private var isFindPending: Bool {
        guard let searchViewModel else { return true }
        return searchViewModel.isSearching || searchViewModel.query != searchQuery
    }

    /// The board the chips filter to, looked up live so a deleted board (its
    /// ID still in scene storage) reads as none.
    private var selectedBoard: Board? {
        guard let storedID = UUID(uuidString: storedBoardID) else { return nil }
        return allBoards.first { $0.id == storedID }
    }

    /// The board chip's board ID; nil for All.
    private var selectedBoardID: UUID? {
        selectedBoard?.id
    }

    private var selectedBoardIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedBoardID },
            set: { storedBoardID = $0?.uuidString ?? "" }
        )
    }

    /// Items scoped to the board filter (if any), before text search
    private var boardFilteredItems: [Item] {
        let base: [Item]
        if let board = selectedBoard {
            base = board.items
        } else {
            base = allItems
        }
        let statusFiltered: [Item]
        if showingArchived {
            statusFiltered = base.filter { $0.status == .archived }
        } else if selectedBoardID != nil {
            // Board views keep their historical status behavior, minus archived
            statusFiltered = base.filter { $0.status != .archived }
        } else {
            // Unkept newsletter issues stay in the Newsletters section
            // until explicitly promoted into the library.
            statusFiltered = base.filter {
                ($0.status == .active || $0.status == .inbox) && !$0.isFeedSuggestion
            }
        }
        return sortOption.sorted(statusFiltered)
    }

    /// Displayed items: every item with a row in the list. A find result
    /// that lists an item under two headings counts it once.
    private var displayedItems: [Item] {
        let scope = boardFilteredItems
        guard isFinding else { return scope }
        var seen = Set<UUID>()
        return findSections(in: scope).flatMap(\.rows).compactMap { row in
            seen.insert(row.item.id).inserted ? row.item : nil
        }
    }

    /// The list: find results while there is a query, otherwise the index.
    private var listSections: [LibraryListSection] {
        let scope = boardFilteredItems
        return isFinding ? findSections(in: scope) : indexSections(for: scope)
    }

    // MARK: - Index

    /// The index: one row per item, under month headings for the date sorts.
    private func indexSections(for items: [Item]) -> [LibraryListSection] {
        guard !items.isEmpty else { return [] }
        let option = sortOption

        guard option.groupsByMonth else {
            return [LibraryListSection(
                id: "index",
                title: nil,
                count: nil,
                rows: items.map { indexRow(for: $0, date: option.date(for: $0), underMonth: false) }
            )]
        }

        return LibraryIndex.monthSections(items) { option.date(for: $0) }.map { month in
            LibraryListSection(
                id: month.id,
                title: month.title,
                count: nil,
                rows: month.elements.map { indexRow(for: $0, date: option.date(for: $0), underMonth: true) }
            )
        }
    }

    private func indexRow(for item: Item, date: Date, underMonth: Bool) -> LibraryListRow {
        LibraryListRow(
            id: item.id.uuidString,
            item: item,
            typeLabel: item.type.indexLabel,
            typeSymbolName: nil,
            isOwn: item.type == .note,
            snippet: nil,
            date: date,
            dateCarriesYear: !underMonth,
            showsBoard: true
        )
    }

    // MARK: - Find Results

    /// What the search found, under the Library's headings, kept to the items
    /// the Library is showing (`scope`: board filter, archived toggle). Boards
    /// whose name matches come first, as rows that apply the board's chip.
    private func findSections(in scope: [Item]) -> [LibraryListSection] {
        guard let searchViewModel else { return [] }

        let exactResults = (searchViewModel.results[.item] ?? []) + (searchViewModel.results[.reflection] ?? [])
        let exact = exactResults.compactMap { findCandidate(for: $0, readsBody: true, idPrefix: "item") }
        let tagged = (searchViewModel.results[.tag] ?? []).flatMap { taggedCandidates(for: $0) }
        let related = searchViewModel.semanticResults.compactMap {
            findCandidate(for: $0, readsBody: false, idPrefix: "related")
        }

        let groups = LibraryFind.groups(
            query: searchViewModel.query,
            exact: exact,
            tagged: tagged,
            related: related,
            allowedItemIDs: Set(scope.map(\.id))
        )

        var sections: [LibraryListSection] = []

        let boardHits = (searchViewModel.results[.board] ?? []).compactMap { result -> Board? in
            guard let board = result.board, !board.isDeleted, board.modelContext != nil else { return nil }
            return board
        }
        let offered = LibraryFind.offeredBoards(
            boardHits,
            query: searchViewModel.query,
            excluding: selectedBoardID,
            id: { $0.id },
            title: { $0.title }
        )
        if !offered.isEmpty {
            sections.append(LibraryListSection(
                id: LibraryFind.boardsGroupID,
                title: LibraryFind.boardsGroupTitle,
                count: offered.count,
                rows: [],
                boardRows: offered.map { LibraryBoardRow(id: "board-\($0.id.uuidString)", board: $0) }
            ))
        }

        for group in groups {
            let rows = group.rows.compactMap { findRow(for: $0) }
            guard !rows.isEmpty else { continue }
            sections.append(LibraryListSection(id: group.id, title: group.kind.title, count: rows.count, rows: rows))
        }
        return sections
    }

    /// A tag hit as one candidate per item carrying the tag, with the tag's
    /// name as the body. Dropped, as other results are, once deleted.
    private func taggedCandidates(for result: SearchResult) -> [LibraryFind.Candidate<SearchResult>] {
        guard let tag = result.tag, !tag.isDeleted, tag.modelContext != nil else { return [] }
        return tag.items.compactMap { item in
            guard !item.isDeleted, item.modelContext != nil else { return nil }
            return LibraryFind.Candidate(
                id: "tag-\(item.id.uuidString)",
                itemID: item.id,
                source: .tag,
                title: item.title,
                isNote: item.type == .note,
                body: tag.name,
                score: result.score,
                payload: SearchResult(
                    type: .item,
                    title: item.title,
                    subtitle: nil,
                    score: result.score,
                    item: item,
                    board: nil,
                    tag: tag,
                    reflection: nil
                )
            )
        }
    }

    /// A search result as a grouping candidate. Results outlive the search
    /// that made them, so one whose item or reflection has since been deleted
    /// is dropped before anything is read from it.
    ///
    /// The candidate's ID, which becomes the row's, is built from the model's
    /// ID rather than the result's: every search makes new results, and the
    /// keyboard highlight has to survive a search re-run for the same query.
    private func findCandidate(
        for result: SearchResult,
        readsBody: Bool,
        idPrefix: String
    ) -> LibraryFind.Candidate<SearchResult>? {
        guard let item = result.item, !item.isDeleted, item.modelContext != nil else { return nil }

        if result.type == .reflection {
            guard let block = result.reflection, !block.isDeleted, block.modelContext != nil else { return nil }
            return LibraryFind.Candidate(
                id: "reflection-\(block.id.uuidString)",
                itemID: item.id,
                source: .reflection,
                title: item.title,
                isNote: false,
                body: block.content,
                score: result.score,
                payload: result
            )
        }

        return LibraryFind.Candidate(
            id: "\(idPrefix)-\(item.id.uuidString)",
            itemID: item.id,
            source: .item,
            title: item.title,
            isNote: item.type == .note,
            body: readsBody ? item.retrievalText : "",
            score: result.score,
            payload: result
        )
    }

    private func findRow(for row: LibraryFind.Row<SearchResult>) -> LibraryListRow? {
        guard let item = row.payload.item else { return nil }

        switch row.source {
        case .reflection:
            return LibraryListRow(
                id: row.id,
                item: item,
                typeLabel: LibraryIndex.reflectionLabel,
                typeSymbolName: LibraryIndex.reflectionSymbolName,
                isOwn: false,
                snippet: row.snippet,
                date: row.payload.reflection?.createdAt ?? item.updatedAt,
                dateCarriesYear: true,
                showsBoard: false
            )
        case .item, .tag:
            return LibraryListRow(
                id: row.id,
                item: item,
                typeLabel: item.type.indexLabel,
                typeSymbolName: nil,
                isOwn: item.type == .note,
                snippet: row.snippet,
                date: item.updatedAt,
                dateCarriesYear: true,
                showsBoard: row.snippet == nil
            )
        }
    }

    // MARK: - Body

    var body: some View {
        libraryLayout
            .alert("Delete Item", isPresented: deleteAlertBinding) {
                deleteAlertButtons
            } message: {
                Text("\"\(itemToDelete?.title ?? "")\" will be permanently deleted.")
            }
            .alert("Delete \(selectedIDs.count) Items", isPresented: $showBulkDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    performBulkDelete()
                }
            } message: {
                Text("The selected items will be permanently deleted.")
            }
            .sheet(isPresented: $showBoardPicker) {
                boardPickerSheet
            }
    }

    private var libraryLayout: some View {
        let sections = listSections
        let rowCount = sections.reduce(0) { $0 + $1.rows.count + $1.boardRows.count }
        // Only "Related in meaning" has rows: say so before it, as the overlay does.
        let onlyRelated = isFinding && !isFindPending
            && sections.first?.id == LibraryFind.GroupKind.related.rawValue

        return VStack(alignment: .leading, spacing: 0) {
            header(resultCount: isFinding && rowCount > 0 ? rowCount : nil)

            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 1)

            ZStack(alignment: .bottom) {
                LibraryListView(
                    sections: sections,
                    emptyState: LibraryEmptyState.resolve(
                        query: searchQuery,
                        isSearching: isFindPending,
                        boardTitle: selectedBoard?.title,
                        showingArchived: showingArchived
                    ),
                    leadLine: onlyRelated ? LibraryEmptyState.nothingMatches(trimmedQuery) : nil,
                    isMultiSelectMode: isMultiSelectMode,
                    selectedIDs: selectedIDs,
                    cursor: cursor,
                    selectedItem: $selectedItem,
                    openedItem: $openedItem,
                    onToggleSelection: { toggleSelection(for: $0) },
                    onEnterMultiSelect: { item in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isMultiSelectMode = true
                            selectedIDs.insert(item.id)
                        }
                    },
                    onDeleteRequest: { itemToDelete = $0 },
                    onApplyBoard: { applyBoard($0) }
                )

                if isMultiSelectMode && !selectedIDs.isEmpty {
                    multiSelectToolbar
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Library")
        .onAppear {
            startFind()
        }
        .onChange(of: searchQuery) { _, _ in
            cursor.highlightedRowID = nil
            runFind()
        }
        .onChange(of: storedBoardID) { _, _ in
            cursor.highlightedRowID = nil
            runFind()
        }
        .onChange(of: showingArchived) { _, _ in
            cursor.highlightedRowID = nil
            runFind()
        }
        .onChange(of: allItems.count) { _, _ in
            runFind()
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveItemWillDelete)) { _ in
            forgetFindResults()
        }
        .onKeyPress(.escape) {
            guard isMultiSelectMode else { return .ignored }
            exitMultiSelect()
            return .handled
        }
    }

    // MARK: - Header

    /// The fixed top of the page: title, find field, then the board filter
    /// with the sort order and the select toggle at its end.
    private func header(resultCount: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(.groveTitle)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            LibraryFindField(
                query: $searchQuery,
                resultCount: resultCount,
                onSubmit: { submitFind() },
                onMoveHighlight: { moveHighlight(by: $0) }
            )
            .padding(.top, Spacing.md)

            HStack(spacing: Spacing.md) {
                LibraryBoardFilterBar(
                    boards: allBoards,
                    selectedBoardID: selectedBoardIDBinding,
                    showingArchived: $showingArchived
                )

                LibrarySortMenu(sortOption: $sortOption)

                selectToggle
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .padding(.top, Spacing.lg)
        .background(Color.bgPrimary)
    }

    /// Select mode toggle
    private var selectToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isMultiSelectMode {
                    exitMultiSelect()
                } else {
                    isMultiSelectMode = true
                }
            }
        } label: {
            Text(isMultiSelectMode ? "Cancel" : "Select")
                .font(.groveMeta)
                .foregroundStyle(isMultiSelectMode ? Color.textPrimary : Color.textSecondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )
    }

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Cancel", role: .cancel) {
            itemToDelete = nil
        }
        Button("Delete", role: .destructive) {
            if let item = itemToDelete {
                // Presentation state (selection, reader, write panel) is
                // cleared by the .groveItemWillDelete observer.
                ItemViewModel(modelContext: modelContext).deleteItem(item)
            }
            itemToDelete = nil
        }
    }

    // MARK: - Multi-Select Helpers

    private func exitMultiSelect() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isMultiSelectMode = false
            selectedIDs = []
        }
    }

    private func toggleSelection(for item: Item) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
            if selectedIDs.isEmpty {
                isMultiSelectMode = false
            }
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func performMove(to board: Board?) {
        let itemVM = ItemViewModel(modelContext: modelContext)
        let itemsToMove = displayedItems.filter { selectedIDs.contains($0.id) }
        itemVM.moveItemsToBoard(itemsToMove, board: board)
        exitMultiSelect()
    }

    /// Currently selected items in multi-select mode
    private var selectedItems: [Item] {
        displayedItems.filter { selectedIDs.contains($0.id) }
    }

    private func performBulkArchive() {
        let newStatus: ItemStatus = showingArchived ? .active : .archived
        for item in selectedItems {
            item.status = newStatus
            item.updatedAt = .now
            if newStatus == .archived {
                if selectedItem?.id == item.id { selectedItem = nil }
                if openedItem?.id == item.id { openedItem = nil }
            }
        }
        try? modelContext.save()
        exitMultiSelect()
    }

    private func performBulkDelete() {
        // Presentation state is cleared per item by the
        // .groveItemWillDelete observer in ContentViewHandlers.
        ItemViewModel(modelContext: modelContext).deleteItems(selectedItems)
        exitMultiSelect()
    }

    // MARK: - Multi-Select Toolbar

    private var multiSelectToolbar: some View {
        HStack(spacing: Spacing.md) {
            Text("\(selectedIDs.count) selected")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))

            Spacer()

            Button {
                showBoardPicker = true
            } label: {
                Label("Move to Board\u{2026}", systemImage: "folder")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textPrimary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button {
                performBulkArchive()
            } label: {
                Label(showingArchived ? "Unarchive" : "Archive",
                      systemImage: showingArchived ? "tray.and.arrow.up" : "archivebox")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                showBulkDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                exitMultiSelect()
            } label: {
                Text("Done")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 1)
        }
    }

    // MARK: - Board Picker Sheet

    /// Multi-select move. `.move` mode replaces board membership (matching
    /// `moveItemsToBoard`) and offers Unfiled as an explicit target.
    private var boardPickerSheet: some View {
        BoardPickerView(
            boards: allBoards,
            mode: .move,
            onSelect: { board in
                showBoardPicker = false
                performMove(to: board)
            },
            onSelectUnfiled: {
                showBoardPicker = false
                performMove(to: nil)
            }
        )
    }

    // MARK: - Find
    //
    // The find field drives `SearchViewModel` the way the search overlay does:
    // every change of text goes through `updateQuery` (the view model
    // debounces, then looks up semantic matches), and return runs the pending
    // search at once. Two things differ, because this page stays up and has
    // filters of its own. The scope is the set of items the Library is
    // showing (`scopeItemIDs`) rather than a board, so the board chips, the
    // archived toggle and the rule that keeps unkept feed items out all hold
    // while searching. And each search reads the store afresh, where the
    // overlay loads its corpus once per presentation.

    private func startFind() {
        guard searchViewModel == nil else { return }
        let viewModel = SearchViewModel(modelContext: modelContext)
        viewModel.resultLimits = .library
        searchViewModel = viewModel
        runFind()
        // A query kept from before the reader was opened: show its results
        // at once rather than after the typing pause.
        if isFinding {
            viewModel.flushPendingSearch()
        }
    }

    /// Hands the field's text to the search, inside the Library's current
    /// filters. An empty field clears the results.
    private func runFind() {
        guard let searchViewModel else { return }
        guard isFinding || !searchViewModel.query.isEmpty else { return }
        searchViewModel.scopeItemIDs = Set(boardFilteredItems.map(\.id))
        searchViewModel.invalidateCorpus()
        searchViewModel.updateQuery(searchQuery)
    }

    // MARK: - Keyboard

    /// Down / Up in the find field: move the highlight through the rows,
    /// without selecting them (selection opens the Info tab).
    private func moveHighlight(by step: Int) {
        cursor.highlightedRowID = LibraryFind.movedHighlight(
            from: cursor.highlightedRowID,
            by: step,
            in: listSections.rowIDs
        )
    }

    /// Return in the find field: run the pending search now, then act on the
    /// highlighted row, if any, as a click on it would.
    private func submitFind() {
        searchViewModel?.flushPendingSearch()
        guard let highlighted = cursor.highlightedRowID else { return }
        let sections = listSections

        if let boardRow = sections.flatMap(\.boardRows).first(where: { $0.id == highlighted }) {
            applyBoard(boardRow.board)
            return
        }
        guard let row = sections.flatMap(\.rows).first(where: { $0.id == highlighted }) else { return }
        if isMultiSelectMode {
            toggleSelection(for: row.item)
        } else {
            selectedItem = row.item
            openedItem = row.item
        }
    }

    /// A board row was chosen: apply its chip. The query was the board's
    /// name, so it is cleared, and the list shows the board.
    private func applyBoard(_ board: Board) {
        cursor.highlightedRowID = nil
        storedBoardID = board.id.uuidString
        searchQuery = ""
    }

    /// An item is about to be deleted. Results hold their items, so drop them
    /// all while the model is still valid; the search runs again after its
    /// usual pause, by which time the item has left the store.
    private func forgetFindResults() {
        guard let searchViewModel, isFinding else { return }
        searchViewModel.clearSearch()
        searchViewModel.invalidateCorpus()
        searchViewModel.updateQuery(searchQuery)
    }
}
