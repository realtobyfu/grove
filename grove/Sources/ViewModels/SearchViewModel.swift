import Foundation
import SwiftData

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
    let item: Item?
    let board: Board?
    let tag: Tag?
    let reflection: ReflectionBlock?
}

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResultType: [SearchResult]] = [:]
    var isSearching = false

    /// Optional board scope — when set, item/reflection results are restricted to this board
    var scopeBoard: Board? {
        didSet {
            if oldValue?.id != scopeBoard?.id {
                cachedCorpus = nil
            }
        }
    }

    private var modelContext: ModelContext
    private let debounceNanoseconds: UInt64
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var cachedCorpus: SearchCorpus?

    private struct SearchCorpus {
        let items: [Item]
        let reflections: [ReflectionBlock]
        let tags: [Tag]
        let boards: [Board]
    }

    init(modelContext: ModelContext, debounceNanoseconds: UInt64 = 250_000_000) {
        self.modelContext = modelContext
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
        let reflectionResults = searchReflections(query: query, reflections: corpus.reflections)
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

    private func searchItems(query: String, items: [Item]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for item in items {
            let titleScore = fuzzyScore(queryLower, in: item.title.lowercased())
            let contentScore = item.content.map { fuzzyScore(queryLower, in: $0.lowercased()) * 0.7 } ?? 0

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

    private func searchReflections(query: String, reflections: [ReflectionBlock]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for block in reflections {
            let contentScore = fuzzyScore(queryLower, in: block.content.lowercased())
            guard contentScore > 0 else { continue }

            let parentTitle = block.item?.title ?? "Unknown item"
            let preview = String(block.content.prefix(80))

            scored.append(SearchResult(
                type: .reflection,
                title: preview,
                subtitle: "\(block.blockType.displayName) on \(parentTitle)",
                score: contentScore,
                item: block.item,
                board: nil,
                tag: nil,
                reflection: block
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(10).map { $0 }
    }

    private func searchTags(query: String, tags: [Tag]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for tag in tags {
            let nameScore = fuzzyScore(queryLower, in: tag.name.lowercased())
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

    private func searchBoards(query: String, boards: [Board]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for board in boards {
            let titleScore = fuzzyScore(queryLower, in: board.title.lowercased())
            let descScore = board.boardDescription.map { fuzzyScore(queryLower, in: $0.lowercased()) * 0.6 } ?? 0
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

    // MARK: - Fuzzy Scoring

    /// Returns a score 0.0–1.0 for how well `query` matches within `text`.
    /// Uses substring matching with bonuses for prefix match and word boundary match.
    private func fuzzyScore(_ query: String, in text: String) -> Double {
        guard !query.isEmpty, !text.isEmpty else { return 0 }

        // Exact match — highest score
        if text == query { return 1.0 }

        // Prefix match
        if text.hasPrefix(query) { return 0.95 }

        // Contains — basic substring match
        if text.contains(query) {
            // Bonus if it starts at a word boundary
            if let range = text.range(of: query) {
                let idx = text.distance(from: text.startIndex, to: range.lowerBound)
                if idx == 0 {
                    return 0.9
                }
                // Check if preceded by space/punctuation (word boundary)
                let charBefore = text[text.index(range.lowerBound, offsetBy: -1)]
                if charBefore == " " || charBefore == "-" || charBefore == "_" || charBefore == "/" {
                    return 0.85
                }
                // General substring match, penalize by position
                let positionPenalty = Double(idx) / Double(text.count) * 0.2
                return max(0.6 - positionPenalty, 0.4)
            }
            return 0.5
        }

        // Word-level matching: check if all query words appear in text
        let queryWords = query.split(separator: " ")
        if queryWords.count > 1 {
            let allFound = queryWords.allSatisfy { word in
                text.contains(word)
            }
            if allFound {
                return 0.55
            }
        }

        // Fuzzy character matching — allow typos/partial matches
        let matchScore = subsequenceMatch(query, in: text)
        if matchScore > 0.5 {
            return matchScore * 0.5
        }

        return 0
    }

    private func loadSearchCorpus() -> SearchCorpus {
        if let cachedCorpus {
            return cachedCorpus
        }

        let boardScopeID = scopeBoard?.id
        var items: [Item] = modelContext.fetchAll()
        if let boardScopeID {
            items = items.filter { item in
                item.boards.contains(where: { $0.id == boardScopeID })
            }
        }

        var reflections: [ReflectionBlock] = modelContext.fetchAll()
        if let boardScopeID {
            reflections = reflections.filter { block in
                guard let parentItem = block.item else { return false }
                return parentItem.boards.contains(where: { $0.id == boardScopeID })
            }
        }

        let tags: [Tag] = modelContext.fetchAll()
        let boards: [Board] = modelContext.fetchAll()

        let corpus = SearchCorpus(
            items: items,
            reflections: reflections,
            tags: tags,
            boards: boards
        )
        cachedCorpus = corpus
        return corpus
    }

    /// Character-by-character subsequence match score
    private func subsequenceMatch(_ query: String, in text: String) -> Double {
        var queryIdx = query.startIndex
        var textIdx = text.startIndex
        var matched = 0

        while queryIdx < query.endIndex && textIdx < text.endIndex {
            if query[queryIdx] == text[textIdx] {
                matched += 1
                queryIdx = query.index(after: queryIdx)
            }
            textIdx = text.index(after: textIdx)
        }

        return Double(matched) / Double(query.count)
    }
}
