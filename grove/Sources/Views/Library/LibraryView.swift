import SwiftUI
import SwiftData
import Combine

// MARK: - Library Sort Option

/// User-selectable sort order for the library list.
/// Search-result ranking (fuzzy score) is unaffected.
enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case dateAdded
    case titleAZ
    case depth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyUpdated: "Recently updated"
        case .dateAdded: "Date added"
        case .titleAZ: "Title A\u{2013}Z"
        case .depth: "Depth"
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
        case .depth:
            items.sorted { $0.depthScore > $1.depthScore }
        }
    }
}

// MARK: - LibraryView

/// Full library: persistent search bar + all items in reverse-chronological order.
/// Boards act as filter chips to narrow the item list.
struct LibraryView: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]

    @State private var searchQuery: String = ""
    @State private var selectedBoardID: UUID? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var filteredResults: [Item] = []
    @State private var isSearching = false
    @State private var showingRevisitFilter = false
    @State private var showingArchived = false
    @State private var itemToDelete: Item?

    @AppStorage("librarySortOption") private var sortOption: LibrarySortOption = .recentlyUpdated

    // Multi-select state
    @State private var isMultiSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBoardPicker = false
    @State private var showBulkDeleteConfirm = false

    // MARK: - Computed

    /// Non-smart boards available as move targets
    private var moveTargetBoards: [Board] {
        allBoards.filter { !$0.isSmart }
    }

    /// Items overdue for resurfacing (spaced repetition queue)
    private var overdueItems: [Item] {
        allItems.filter { $0.isResurfacingEligible && $0.isResurfacingOverdue }
    }

    /// Items scoped to the board filter (if any), before text search
    private var boardFilteredItems: [Item] {
        if showingRevisitFilter {
            return overdueItems
        }
        let base: [Item]
        if let boardID = selectedBoardID,
           let board = allBoards.first(where: { $0.id == boardID }) {
            base = board.isSmart
                ? BoardViewModel.smartBoardItems(for: board, from: allItems)
                : board.items
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

    /// Displayed items: search-filtered or default
    private var displayedItems: [Item] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return boardFilteredItems
        }
        return filteredResults
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
        VStack(spacing: 0) {
            LibrarySearchBar(
                searchQuery: $searchQuery,
                sortOption: $sortOption,
                isSearching: isSearching,
                isMultiSelectMode: isMultiSelectMode,
                onToggleMultiSelect: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isMultiSelectMode {
                            exitMultiSelect()
                        } else {
                            isMultiSelectMode = true
                        }
                    }
                }
            )

            if !overdueItems.isEmpty {
                LibraryRevisitBanner(
                    overdueCount: overdueItems.count,
                    showingRevisitFilter: $showingRevisitFilter,
                    selectedBoardID: $selectedBoardID,
                    searchQuery: $searchQuery
                )
            }

            if !showingRevisitFilter {
                LibraryBoardFilterBar(
                    boards: allBoards,
                    selectedBoardID: $selectedBoardID,
                    showingArchived: $showingArchived
                )
            }

            Divider()

            ZStack(alignment: .bottom) {
                LibraryListView(
                    displayedItems: displayedItems,
                    searchQuery: searchQuery,
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Library")
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .onChange(of: selectedBoardID) { _, _ in
            scheduleSearch(query: searchQuery)
        }
        .onChange(of: showingArchived) { _, _ in
            scheduleSearch(query: searchQuery)
        }
        .onChange(of: allItems.count) { _, _ in
            scheduleSearch(query: searchQuery)
        }
        .onKeyPress(.escape) {
            guard isMultiSelectMode else { return .ignored }
            exitMultiSelect()
            return .handled
        }
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
                if selectedItem?.id == item.id { selectedItem = nil }
                if openedItem?.id == item.id { openedItem = nil }
                modelContext.delete(item)
                try? modelContext.save()
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
        for item in selectedItems {
            if selectedItem?.id == item.id { selectedItem = nil }
            if openedItem?.id == item.id { openedItem = nil }
            modelContext.delete(item)
        }
        try? modelContext.save()
        exitMultiSelect()
    }

    // MARK: - Multi-Select Toolbar

    private var multiSelectToolbar: some View {
        HStack(spacing: Spacing.md) {
            Text("\(selectedIDs.count) selected")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())

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
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Board Picker Sheet

    private var boardPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Move to Board")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    showBoardPicker = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Unfiled option
                    Button {
                        showBoardPicker = false
                        performMove(to: nil)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.groveBody)
                                .foregroundStyle(Color.textMuted)
                                .frame(width: 20)
                            Text("Unfiled")
                                .font(.groveBody)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 42)

                    ForEach(moveTargetBoards) { board in
                        Button {
                            showBoardPicker = false
                            performMove(to: board)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: board.icon ?? "folder")
                                    .font(.groveBody)
                                    .foregroundStyle(Color.textMuted)
                                    .frame(width: 20)
                                Text(board.title)
                                    .font(.groveBody)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if board.id != moveTargetBoards.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: min(CGFloat(moveTargetBoards.count + 1) * 48 + 60, 400))
    }

    // MARK: - Debounced Search

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        searchTask = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filteredResults = []
            isSearching = false
            return
        }

        isSearching = true
        let candidates = boardFilteredItems
        let ctx = modelContext

        searchTask = MainActorTaskScheduler.schedule(after: .milliseconds(300)) {
            filteredResults = performSearch(query: trimmed, candidates: candidates, context: ctx)
            isSearching = false
        }
    }

    private func performSearch(query: String, candidates: [Item], context: ModelContext) -> [Item] {
        let lower = query.lowercased()

        // Score each item
        var scored: [(item: Item, score: Double)] = []

        // Fetch reflection content for content matching
        let reflectionDescriptor = FetchDescriptor<ReflectionBlock>()
        let allReflections = (try? context.fetch(reflectionDescriptor)) ?? []
        let reflectionsByItem: [UUID: [ReflectionBlock]] = Dictionary(grouping: allReflections) { block in
            block.item?.id ?? UUID()
        }

        for item in candidates {
            var score: Double = 0

            // Title match (highest weight)
            let titleScore = FuzzySearchScorer.score(normalizedQuery: lower, in: item.title.lowercased()) * 1.0
            score = max(score, titleScore)

            // Content match
            if let content = item.content {
                let contentScore = FuzzySearchScorer.score(normalizedQuery: lower, in: content.lowercased()) * 0.7
                score = max(score, contentScore)
            }

            // Tag match
            for tag in item.tags {
                let tagScore = FuzzySearchScorer.score(normalizedQuery: lower, in: tag.name.lowercased()) * 0.8
                score = max(score, tagScore)
            }

            // Reflection content match
            if let reflections = reflectionsByItem[item.id] {
                for block in reflections {
                    let reflScore = FuzzySearchScorer.score(normalizedQuery: lower, in: block.content.lowercased()) * 0.6
                    score = max(score, reflScore)
                }
            }

            if score > 0 {
                scored.append((item: item, score: score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.item)
    }
}
