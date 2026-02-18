import SwiftUI
import SwiftData
import Combine

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

    // MARK: - Computed

    /// Items scoped to the board filter (if any), before text search
    private var boardFilteredItems: [Item] {
        guard let boardID = selectedBoardID,
              let board = allBoards.first(where: { $0.id == boardID }) else {
            return allItems.filter { $0.status == .active || $0.status == .inbox }
        }
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
        }
        return board.items.sorted { $0.updatedAt > $1.updatedAt }
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
        VStack(spacing: 0) {
            searchBar
            if !allBoards.isEmpty {
                boardFilterBar
            }
            Divider()
            itemList
        }
        .navigationTitle("Library")
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .onChange(of: selectedBoardID) { _, _ in
            scheduleSearch(query: searchQuery)
        }
        .onChange(of: allItems.count) { _, _ in
            scheduleSearch(query: searchQuery)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: isSearching ? "hourglass" : "magnifyingglass")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .animation(.easeInOut(duration: 0.15), value: isSearching)

            TextField("Search titles, content, tags, reflections…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(Color.bgPrimary)
    }

    // MARK: - Board Filter Bar

    private var boardFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // "All" chip
                boardChip(title: "All", boardID: nil)

                ForEach(allBoards) { board in
                    boardChip(title: board.title, boardID: board.id)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.bgPrimary)
    }

    private func boardChip(title: String, boardID: UUID?) -> some View {
        let isActive = selectedBoardID == boardID
        return Button {
            selectedBoardID = boardID
        } label: {
            Text(title)
                .font(.groveTag)
                .foregroundStyle(isActive ? Color.textInverse : Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.bgTagActive : Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Item List

    @ViewBuilder
    private var itemList: some View {
        if displayedItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedItems) { item in
                        libraryRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openedItem = item
                                selectedItem = item
                            }
                            .onTapGesture(count: 1) {
                                selectedItem = item
                            }
                            .selectedItemStyle(selectedItem?.id == item.id)
                        Divider()
                            .padding(.leading, 40)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private func libraryRow(item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Title with optional search highlight indication
                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    // Board membership
                    if let firstBoard = item.boards.first {
                        Text(firstBoard.title)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }

                    if !item.tags.isEmpty && item.boards.first != nil {
                        Text("·")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Tags (first 2)
                    ForEach(Array(item.tags.prefix(2)), id: \.id) { tag in
                        Text(tag.name)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if item.tags.count > 2 {
                        Text("+\(item.tags.count - 2)")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            // Date
            Text(item.updatedAt.relativeShort)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)

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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: searchQuery.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.textTertiary)

            if searchQuery.isEmpty {
                Text("Your Library")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Capture items to start building your knowledge base.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("No results for \"\(searchQuery)\"")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Try different keywords or clear the board filter.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Debounced Search

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filteredResults = []
            isSearching = false
            return
        }

        isSearching = true
        let candidates = boardFilteredItems
        let ctx = modelContext

        searchTask = Task {
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let results = await performSearch(query: trimmed, candidates: candidates, context: ctx)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                filteredResults = results
                isSearching = false
            }
        }
    }

    private func performSearch(query: String, candidates: [Item], context: ModelContext) async -> [Item] {
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
            let titleScore = fuzzyScore(lower, in: item.title.lowercased()) * 1.0
            score = max(score, titleScore)

            // Content match
            if let content = item.content {
                let contentScore = fuzzyScore(lower, in: content.lowercased()) * 0.7
                score = max(score, contentScore)
            }

            // Tag match
            for tag in item.tags {
                let tagScore = fuzzyScore(lower, in: tag.name.lowercased()) * 0.8
                score = max(score, tagScore)
            }

            // Reflection content match
            if let reflections = reflectionsByItem[item.id] {
                for block in reflections {
                    let reflScore = fuzzyScore(lower, in: block.content.lowercased()) * 0.6
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

    /// Simple fuzzy scorer: exact > prefix > substring > word-level
    private func fuzzyScore(_ query: String, in text: String) -> Double {
        guard !query.isEmpty, !text.isEmpty else { return 0 }
        if text == query { return 1.0 }
        if text.hasPrefix(query) { return 0.95 }
        if text.contains(query) {
            if let range = text.range(of: query) {
                let idx = text.distance(from: text.startIndex, to: range.lowerBound)
                if idx == 0 { return 0.9 }
                let before = text[text.index(range.lowerBound, offsetBy: -1)]
                if before == " " || before == "-" || before == "_" { return 0.85 }
                let penalty = Double(idx) / Double(text.count) * 0.2
                return max(0.6 - penalty, 0.4)
            }
            return 0.5
        }
        let queryWords = query.split(separator: " ")
        if queryWords.count > 1 && queryWords.allSatisfy({ text.contains($0) }) {
            return 0.55
        }
        return 0
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeShort: String {
        let now = Date()
        let diff = now.timeIntervalSince(self)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
