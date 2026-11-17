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

// MARK: - LibraryView

/// The Library: the index of everything saved, and the place you search it.
///
/// With nothing in the find field the page lists every item one to a line,
/// under month headings for the two date sorts. With a query it lists what
/// `SearchViewModel` finds, grouped by where the match is (`LibraryFind`).
/// Boards act as filter chips on both.
struct LibraryView: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]

    @State private var searchQuery: String = ""
    /// The search behind the find field: the same view model the search
    /// overlay drives, scoped to the items the filters show. Built when the
    /// page appears.
    @State private var searchViewModel: SearchViewModel?
    @State private var selectedBoardID: UUID? = nil
    @State private var showingArchived = false
    @State private var itemToDelete: Item?

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

    /// The board the chips filter to, looked up live so a deleted board reads as none.
    private var selectedBoard: Board? {
        guard let selectedBoardID else { return nil }
        return allBoards.first { $0.id == selectedBoardID }
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
            isOwn: item.type == .note,
            snippet: nil,
            date: date,
            dateCarriesYear: !underMonth,
            showsBoard: true
        )
    }

    // MARK: - Find Results

    /// What the search found, under the Library's headings, kept to the items
    /// the Library is showing (`scope`: board filter, archived toggle).
    private func findSections(in scope: [Item]) -> [LibraryListSection] {
        guard let searchViewModel else { return [] }

        let exactResults = (searchViewModel.results[.item] ?? []) + (searchViewModel.results[.reflection] ?? [])
        let exact = exactResults.compactMap { findCandidate(for: $0, readsBody: true) }
        let related = searchViewModel.semanticResults.compactMap { findCandidate(for: $0, readsBody: false) }

        let groups = LibraryFind.groups(
            query: searchViewModel.query,
            exact: exact,
            related: related,
            allowedItemIDs: Set(scope.map(\.id))
        )

        return groups.compactMap { group -> LibraryListSection? in
            let rows = group.rows.compactMap { findRow(for: $0) }
            guard !rows.isEmpty else { return nil }
            return LibraryListSection(id: group.id, title: group.kind.title, count: rows.count, rows: rows)
        }
    }

    /// A search result as a grouping candidate. Results outlive the search
    /// that made them, so one whose item or reflection has since been deleted
    /// is dropped before anything is read from it.
    private func findCandidate(
        for result: SearchResult,
        readsBody: Bool
    ) -> LibraryFind.Candidate<SearchResult>? {
        guard let item = result.item, !item.isDeleted, item.modelContext != nil else { return nil }

        if result.type == .reflection {
            guard let block = result.reflection, !block.isDeleted, block.modelContext != nil else { return nil }
            return LibraryFind.Candidate(
                id: result.id.uuidString,
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
            id: result.id.uuidString,
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
                isOwn: false,
                snippet: row.snippet,
                date: row.payload.reflection?.createdAt ?? item.updatedAt,
                dateCarriesYear: true,
                showsBoard: false
            )
        case .item:
            return LibraryListRow(
                id: row.id,
                item: item,
                typeLabel: item.type.indexLabel,
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
        let rowCount = sections.reduce(0) { $0 + $1.rows.count }
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
                    selectedItem: $selectedItem,
                    openedItem: $openedItem,
                    onToggleSelection: { toggleSelection(for: $0) },
                    onEnterMultiSelect: { item in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isMultiSelectMode = true
                            selectedIDs.insert(item.id)
                        }
                    },
                    onDeleteRequest: { itemToDelete = $0 }
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
            runFind()
        }
        .onChange(of: selectedBoardID) { _, _ in
            runFind()
        }
        .onChange(of: showingArchived) { _, _ in
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
                onSubmit: { searchViewModel?.flushPendingSearch() }
            )
            .padding(.top, Spacing.md)

            HStack(spacing: Spacing.md) {
                LibraryBoardFilterBar(
                    boards: allBoards,
                    selectedBoardID: $selectedBoardID,
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
        searchViewModel = SearchViewModel(modelContext: modelContext)
        runFind()
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
