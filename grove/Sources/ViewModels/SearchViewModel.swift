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

/// An embedding-index hit: an item ID and its cosine similarity to the query.
struct SemanticCandidate: Sendable, Equatable {
    let id: UUID
    let score: Double
}

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResultType: [SearchResult]] = [:]
    /// Items the on-device embedding index places near the query that the fuzzy
    /// pass did not already return. Shown as "Related by meaning" below the exact
    /// matches. Empty for queries under `semanticMinimumQueryLength` characters
    /// or when the index holds nothing comparable.
    var semanticResults: [SearchResult] = []
    var isSearching = false

    // MARK: Semantic search tuning

    /// Cosine-similarity floor for "Related by meaning". NLEmbedding sentence
    /// vectors score a short query against multi-paragraph item text low: on a
    /// 286-item index, strongly topical neighbours land at 0.40–0.50 while every
    /// query, keyboard noise included, has a tail of 0.30–0.38 hits. 0.40 keeps
    /// the former and cuts the tail (0–3 hits for most queries). The index's own
    /// 0.55 default returns nothing for typed queries.
    nonisolated static let semanticScoreThreshold: Double = 0.40
    nonisolated static let semanticResultLimit = 8
    nonisolated static let semanticMinimumQueryLength = 3
    /// Index hits requested before fuzzy/archived exclusions are applied.
    private nonisolated static let semanticCandidatePoolSize = 64

    /// Optional board scope — when set, item/reflection results are restricted to this board
    var scopeBoard: Board? {
        didSet {
            if oldValue?.id != scopeBoard?.id {
                cachedCorpus = nil
                cancelSemanticSearch()
            }
        }
    }

    private var modelContext: ModelContext
    private let debounceNanoseconds: UInt64
    private let semanticDebounceNanoseconds: UInt64
    private let embeddingIndex: EmbeddingIndexService
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var cachedCorpus: SearchCorpus?
    private var semanticTask: Task<Void, Never>?
    /// The query that `semanticResults`, or the semantic lookup in flight, belongs to.
    private var semanticQuery: String?

    private struct SearchCorpus {
        let items: [Item]
        let reflections: [ReflectionBlock]
        let tags: [Tag]
        let boards: [Board]
    }

    init(
        modelContext: ModelContext,
        debounceNanoseconds: UInt64 = 250_000_000,
        semanticDebounceNanoseconds: UInt64 = 150_000_000,
        embeddingIndex: EmbeddingIndexService = .shared
    ) {
        self.modelContext = modelContext
        self.debounceNanoseconds = debounceNanoseconds
        self.semanticDebounceNanoseconds = semanticDebounceNanoseconds
        self.embeddingIndex = embeddingIndex
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
        clearSemanticResults()
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
            clearSemanticResults()
            return
        }

        cancelSemanticSearchIfStale(for: trimmed)
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
            clearSemanticResults()
            return
        }

        cancelSemanticSearchIfStale(for: trimmed)
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

        // Reflection hits navigate to their parent item, so that item counts as shown.
        let fuzzyItemIDs = Set(grouped.values.joined().compactMap { $0.item?.id })
        scheduleSemanticSearch(query: query, fuzzyItemIDs: fuzzyItemIDs)
    }

    /// Exact-match count (fuzzy results only).
    var totalResultCount: Int {
        results.values.reduce(0) { $0 + $1.count }
    }

    /// True when either the exact matches or "Related by meaning" have rows to show.
    var hasAnyResults: Bool {
        totalResultCount > 0 || !semanticResults.isEmpty
    }

    // MARK: - Semantic Search

    /// Merge rule for "Related by meaning": keep candidates scoring at or above
    /// `threshold` that are neither already shown as fuzzy matches nor excluded,
    /// highest score first (ties by ID for a stable order), at most `limit`.
    /// A candidate listed twice keeps its best score.
    nonisolated static func semanticMatches(
        candidates: [SemanticCandidate],
        fuzzyIDs: Set<UUID>,
        excludedIDs: Set<UUID>,
        threshold: Double,
        limit: Int
    ) -> [SemanticCandidate] {
        guard limit > 0 else { return [] }

        var bestScores: [UUID: Double] = [:]
        for candidate in candidates
        where candidate.score >= threshold
            && !fuzzyIDs.contains(candidate.id)
            && !excludedIDs.contains(candidate.id) {
            bestScores[candidate.id] = max(bestScores[candidate.id] ?? candidate.score, candidate.score)
        }

        return bestScores
            .map { SemanticCandidate(id: $0.key, score: $0.value) }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Runs the embedding lookup for a query whose fuzzy results just landed.
    private func scheduleSemanticSearch(query: String, fuzzyItemIDs: Set<UUID>) {
        guard query.count >= Self.semanticMinimumQueryLength else {
            clearSemanticResults()
            return
        }
        // Same query re-run (return pressed, flush): keep what is shown or in
        // flight so a keyboard selection on a semantic row survives.
        guard query != semanticQuery else { return }

        clearSemanticResults()
        semanticQuery = query

        let debounce = semanticDebounceNanoseconds
        let index = embeddingIndex
        let poolSize = Self.semanticCandidatePoolSize
        let threshold = Self.semanticScoreThreshold
        semanticTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounce)
            } catch {
                return
            }
            guard !Task.isCancelled, self != nil else { return }

            let hits = await index.search(query: query, limit: poolSize, minScore: threshold)

            guard !Task.isCancelled, let self, self.semanticQuery == query else { return }
            self.applySemanticHits(hits, fuzzyItemIDs: fuzzyItemIDs)
            self.semanticTask = nil
        }
    }

    private func applySemanticHits(_ hits: [(id: UUID, score: Double)], fuzzyItemIDs: Set<UUID>) {
        let items = loadSearchCorpus().items
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let excludedIDs = Set(items.lazy
            .filter { $0.status == .archived || $0.status == .dismissed }
            .map(\.id))

        // Only hits the corpus holds are candidates, which also applies the board scope.
        let candidates = hits.compactMap { hit in
            itemsByID[hit.id] == nil ? nil : SemanticCandidate(id: hit.id, score: hit.score)
        }
        let matches = Self.semanticMatches(
            candidates: candidates,
            fuzzyIDs: fuzzyItemIDs,
            excludedIDs: excludedIDs,
            threshold: Self.semanticScoreThreshold,
            limit: Self.semanticResultLimit
        )

        semanticResults = matches.compactMap { match in
            guard let item = itemsByID[match.id] else { return nil }
            return SearchResult(
                type: .item,
                title: item.title,
                subtitle: Self.subtitle(for: item),
                score: match.score,
                item: item,
                board: nil,
                tag: nil,
                reflection: nil
            )
        }
    }

    /// A new query makes the semantic lookup in flight stale. Rows already on
    /// screen stay until the fuzzy pass for the new query lands, so the section
    /// does not blink on every keystroke.
    private func cancelSemanticSearchIfStale(for query: String) {
        guard query != semanticQuery else { return }
        cancelSemanticSearch()
    }

    private func cancelSemanticSearch() {
        semanticTask?.cancel()
        semanticTask = nil
        semanticQuery = nil
    }

    private func clearSemanticResults() {
        cancelSemanticSearch()
        if !semanticResults.isEmpty {
            semanticResults = []
        }
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
            let titleScore = FuzzySearchScorer.score(normalizedQuery: queryLower, in: item.title.lowercased())
            let contentScore = FuzzySearchScorer.score(
                normalizedQuery: queryLower,
                in: item.retrievalText.lowercased()
            ) * 0.7

            let bestScore = max(titleScore, contentScore)
            guard bestScore > 0 else { continue }

            scored.append(SearchResult(
                type: .item,
                title: item.title,
                subtitle: Self.subtitle(for: item),
                score: bestScore,
                item: item,
                board: nil,
                tag: nil,
                reflection: nil
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(15).map { $0 }
    }

    private static func subtitle(for item: Item) -> String? {
        if let url = item.sourceURL, !url.isEmpty {
            return url
        } else if let preview = item.previewText {
            return String(preview.prefix(80))
        } else {
            return item.type.rawValue.capitalized
        }
    }

    private func searchReflections(query: String, reflections: [ReflectionBlock]) -> [SearchResult] {
        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for block in reflections {
            let contentScore = FuzzySearchScorer.score(normalizedQuery: queryLower, in: block.content.lowercased())
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

    private func searchBoards(query: String, boards: [Board]) -> [SearchResult] {
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

}
