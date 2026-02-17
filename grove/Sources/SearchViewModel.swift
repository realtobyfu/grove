import Foundation
import SwiftData

/// Represents a single search result with its source type and relevance score.
enum SearchResultType: String, Sendable {
    case item = "Items"
    case annotation = "Annotations"
    case tag = "Tags"
    case board = "Boards"

    var iconName: String {
        switch self {
        case .item: "doc"
        case .annotation: "note.text"
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
    let annotation: Annotation?
}

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResultType: [SearchResult]] = [:]
    var isSearching = false

    /// Optional board scope — when set, item/annotation results are restricted to this board
    var scopeBoard: Board?

    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Perform search across all entity types
    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = [:]
            return
        }

        isSearching = true
        defer { isSearching = false }

        var grouped: [SearchResultType: [SearchResult]] = [:]

        // Search items (titles + content)
        let itemResults = searchItems(query: trimmed)
        if !itemResults.isEmpty {
            grouped[.item] = itemResults
        }

        // Search annotations
        let annotationResults = searchAnnotations(query: trimmed)
        if !annotationResults.isEmpty {
            grouped[.annotation] = annotationResults
        }

        // Search tags
        let tagResults = searchTags(query: trimmed)
        if !tagResults.isEmpty {
            grouped[.tag] = tagResults
        }

        // Search boards
        let boardResults = searchBoards(query: trimmed)
        if !boardResults.isEmpty {
            grouped[.board] = boardResults
        }

        results = grouped
    }

    var totalResultCount: Int {
        results.values.reduce(0) { $0 + $1.count }
    }

    /// Ordered section types for display
    var orderedSections: [SearchResultType] {
        [.item, .annotation, .board, .tag].filter { results[$0] != nil }
    }

    // MARK: - Entity Searches

    private func searchItems(query: String) -> [SearchResult] {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? modelContext.fetch(descriptor) else { return [] }

        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for item in items {
            // If scoped to a board, filter
            if let scope = scopeBoard {
                guard item.boards.contains(where: { $0.id == scope.id }) else { continue }
            }

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
                annotation: nil
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(15).map { $0 }
    }

    private func searchAnnotations(query: String) -> [SearchResult] {
        let descriptor = FetchDescriptor<Annotation>()
        guard let annotations = try? modelContext.fetch(descriptor) else { return [] }

        let queryLower = query.lowercased()
        var scored: [SearchResult] = []

        for annotation in annotations {
            // If scoped to a board, filter by the annotation's parent item's boards
            if let scope = scopeBoard {
                guard let parentItem = annotation.item,
                      parentItem.boards.contains(where: { $0.id == scope.id }) else { continue }
            }

            let contentScore = fuzzyScore(queryLower, in: annotation.content.lowercased())
            guard contentScore > 0 else { continue }

            let parentTitle = annotation.item?.title ?? "Unknown item"
            let preview = String(annotation.content.prefix(80))

            scored.append(SearchResult(
                type: .annotation,
                title: preview,
                subtitle: "on \(parentTitle)",
                score: contentScore,
                item: annotation.item,
                board: nil,
                tag: nil,
                annotation: annotation
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(10).map { $0 }
    }

    private func searchTags(query: String) -> [SearchResult] {
        // Tags are not scoped to boards
        let descriptor = FetchDescriptor<Tag>()
        guard let tags = try? modelContext.fetch(descriptor) else { return [] }

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
                annotation: nil
            ))
        }

        return scored.sorted { $0.score > $1.score }.prefix(8).map { $0 }
    }

    private func searchBoards(query: String) -> [SearchResult] {
        let descriptor = FetchDescriptor<Board>()
        guard let boards = try? modelContext.fetch(descriptor) else { return [] }

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
                annotation: nil
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
