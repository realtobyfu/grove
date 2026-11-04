import Foundation
import SQLiteData

/// Represents a single search result with its source type and relevance score.
enum SearchResultType: String, Sendable {
    case item = "Items"
    case reflection = "Reflections"
    case tag = "Tags"
    case board = "Boards"

    var iconName: String {
        switch self {
        case .item: "doc"
        case .reflection: "text.alignleft"
        case .tag: "tag"
        case .board: "folder"
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let type: SearchResultType
    let title: String
    let subtitle: String?
    let score: Double
    // Navigation targets — one of these will be non-nil
    let item: ItemGraph?
    let board: BoardGraph?
    let tag: TagGraph?
    let reflection: ReflectionBlock?
}

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResultType: [SearchResult]] = [:]
    var isSearching = false

    /// Optional board scope — when set, item/reflection results are restricted to this board
    var scopeBoard: BoardGraph? {
        didSet {
            if oldValue?.id != scopeBoard?.id {
                cachedCorpus = nil
            }
        }
    }

    private let database: any DatabaseWriter
    private let debounceNanoseconds: UInt64
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var cachedCorpus: SearchCorpus?

    private struct SearchCorpus {
        let items: [ItemGraph]
        let reflections: [ReflectionBlock]
        let tags: [TagGraph]
        let boards: [BoardGraph]
        /// Resolves a reflection's parent, which the row only knows by ID.
        let library: Library
    }

    init(database: any DatabaseWriter = AppDatabase.current, debounceNanoseconds: UInt64 = 250_000_000) {
        self.database = database
        self.debounceNanoseconds = debounceNanoseconds
    }

    /// Debounced query update with cancellation for responsive typing.
    func updateQuery(_ newValue: String) {
        if query != newValue {
            query = newValue
        }
        scheduleSearch()
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1
        query = ""
        results = [:]
        isSearching = false
    }

    /// Preserve compatibility for existing call sites that trigger an immediate search.
    func search() {
        flushPendingSearch()
    }

    /// Runs the latest query immediately (used on submit/return).
    func flushPendingSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1

        let generation = searchGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = [:]
            isSearching = false
            return
        }

        isSearching = true
        performSearchNow(query: trimmed, generation: generation)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1

        let generation = searchGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = [:]
            isSearching = false
            return
        }

        isSearching = true
        let debounce = debounceNanoseconds
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.performSearchNow(query: trimmed, generation: generation)
        }
    }

    private func performSearchNow(query: String, generation: Int) {
        let corpus = loadSearchCorpus()

        var grouped: [SearchResultType: [SearchResult]] = [:]

        // Search items (titles + content)
        let itemResults = searchItems(query: query, items: corpus.items)
        if !itemResults.isEmpty {
            grouped[.item] = itemResults
        }

        // Search reflections
        let reflectionResults = searchReflections(query: query, reflections: corpus.reflections, library: corpus.library)
        if !reflectionResults.isEmpty {
            grouped[.reflection] = reflectionResults
        }

        // Search tags
        let tagResults = searchTags(query: query, tags: corpus.tags)
        if !tagResults.isEmpty {
            grouped[.tag] = tagResults
        }

        // Search boards
        let boardResults = searchBoards(query: query, boards: corpus.boards)
        if !boardResults.isEmpty {
            grouped[.board] = boardResults
        }

        guard generation == searchGeneration else { return }
        results = grouped
        isSearching = false
        searchTask = nil
    }

    var totalResultCount: Int {
        results.values.reduce(0) { $0 + $1.count }
    }

    /// Ordered section types for display
    var orderedSections: [SearchResultType] {
        [.item, .reflection, .board, .tag].filter { results[$0] != nil }
    }

    // MARK: - Entity Searches

    private func searchItems(query: String, items: [ItemGraph]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for item in items {
            let titleScore = FuzzySearchScorer.score(normalizedQuery: queryLower, in: item.title.lowercased())
            let contentScore = item.content.map {
                FuzzySearchScorer.score(normalizedQuery: queryLower, in: $0.lowercased()) * 0.7
            } ?? 0

            let bestScore = max(titleScore, contentScore)
            guard bestScore > 0 else { continue }

            let subtitle: String?
            if let url = item.sourceURL, !url.isEmpty {
                subtitle = url
            } else if let content = item.content, !content.isEmpty {
                subtitle = String(content.prefix(80))
            } else {
                subtitle = item.type.rawValue.capitalized
            }

            scored.append(SearchResult(
                type: .item,
                title: item.title,
                subtitle: subtitle,
                score: bestScore,
                item: item,
                board: nil,
                tag: nil,
                reflection: nil
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(15).map { $0 }
    }

    private func searchReflections(query: String, reflections: [ReflectionBlock], library: Library) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for block in reflections {
            let contentScore = FuzzySearchScorer.score(normalizedQuery: queryLower, in: block.content.lowercased())
            guard contentScore > 0 else { continue }

            let parentItem = library.item(block.itemID)
            let parentTitle = parentItem?.title ?? "Unknown item"
            let preview = String(block.content.prefix(80))

            scored.append(SearchResult(
                type: .reflection,
                title: preview,
                subtitle: "\(block.blockType.displayName) on \(parentTitle)",
                score: contentScore,
                item: parentItem,
                board: nil,
                tag: nil,
                reflection: block
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(10).map { $0 }
    }

    private func searchTags(query: String, tags: [TagGraph]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for tag in tags {
            let nameScore = FuzzySearchScorer.score(normalizedQuery: queryLower, in: tag.name.lowercased())
            guard nameScore > 0 else { continue }

            scored.append(SearchResult(
                type: .tag,
                title: tag.name,
                subtitle: "\(tag.items.count) items \u{2022} \(tag.category.displayName)",
                score: nameScore,
                item: nil,
                board: nil,
                tag: tag,
                reflection: nil
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(8).map { $0 }
    }

    private func searchBoards(query: String, boards: [BoardGraph]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for board in boards {
            let titleScore = FuzzySearchScorer.score(normalizedQuery: queryLower, in: board.title.lowercased())
            let descScore = board.boardDescription.map {
                FuzzySearchScorer.score(normalizedQuery: queryLower, in: $0.lowercased()) * 0.6
            } ?? 0
            let bestScore = max(titleScore, descScore)
            guard bestScore > 0 else { continue }

            scored.append(SearchResult(
                type: .board,
                title: board.title,
                subtitle: "\(board.items.count) items",
                score: bestScore,
                item: nil,
                board: board,
                tag: nil,
                reflection: nil
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(5).map { $0 }
    }

    private func loadSearchCorpus() -> SearchCorpus {
        if let cachedCorpus {
            return cachedCorpus
        }

        // One read, kept until the scope changes, so typing never touches the
        // database. Reflections come from their table rather than the library
        // because the library only has the ones attached to an item.
        let (library, allReflections) = database.attemptRead { db in
            (try Library.fetch(db), try ReflectionBlock.all.fetchAll(db))
        } ?? (Library(), [])

        let boardScopeID = scopeBoard?.id
        var items = library.items
        if let boardScopeID {
            items = items.filter { $0.boardID == boardScopeID }
        }

        var reflections = allReflections
        if let boardScopeID {
            reflections = reflections.filter { block in
                library.item(block.itemID)?.boardID == boardScopeID
            }
        }

        let corpus = SearchCorpus(
            items: items,
            reflections: reflections,
            tags: library.tags,
            boards: library.boards,
            library: library
        )
        cachedCorpus = corpus
        return corpus
    }

}
