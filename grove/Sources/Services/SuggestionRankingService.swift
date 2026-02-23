import Foundation
import SwiftData

@MainActor
@Observable
final class SuggestionRankingService {
    static let shared = SuggestionRankingService()

    struct ScoredSuggestion: Identifiable {
        let item: Item
        let score: Double
        var id: UUID { item.id }
    }

    func rankSuggestions(in context: ModelContext) -> [ScoredSuggestion] {
        let suggestions = fetchSuggestions(in: context)
        guard !suggestions.isEmpty else { return [] }

        let userTags = fetchUserTagVocabulary(in: context)
        let domainKeepRates = computeDomainKeepRates(in: context)
        let boardThemes = fetchBoardThemes(in: context)

        var scored: [ScoredSuggestion] = []

        for item in suggestions {
            let score = computeScore(
                item: item,
                userTags: userTags,
                domainKeepRates: domainKeepRates,
                boardThemes: boardThemes
            )
            scored.append(ScoredSuggestion(item: item, score: score))
        }

        return scored.sorted { $0.score > $1.score }
    }

    // MARK: - Scoring

    private func computeScore(
        item: Item,
        userTags: Set<String>,
        domainKeepRates: [String: Double],
        boardThemes: Set<String>
    ) -> Double {
        var score = 0.0

        // Tag overlap (0.35 weight)
        score += tagOverlapScore(item: item, userTags: userTags) * 0.35

        // Domain trust (0.25 weight)
        score += domainTrustScore(item: item, domainKeepRates: domainKeepRates) * 0.25

        // Content depth (0.20 weight)
        score += contentDepthScore(item: item) * 0.20

        // Recency (0.10 weight)
        score += recencyScore(item: item) * 0.10

        // Board alignment (0.10 weight)
        score += boardAlignmentScore(item: item, boardThemes: boardThemes) * 0.10

        return min(1.0, max(0.0, score))
    }

    private func tagOverlapScore(item: Item, userTags: Set<String>) -> Double {
        guard !userTags.isEmpty else { return 0.3 } // Neutral if no tags exist

        // Use title + description keywords as proxy for suggestion tags
        let keywords = extractKeywords(from: item)
        guard !keywords.isEmpty else { return 0.1 }

        let overlap = keywords.intersection(userTags)
        let ratio = Double(overlap.count) / Double(max(keywords.count, 1))
        return min(1.0, ratio * 2.0) // Scale up — even partial overlap is meaningful
    }

    private func domainTrustScore(item: Item, domainKeepRates: [String: Double]) -> Double {
        guard let domain = extractDomain(from: item) else { return 0.3 }
        return domainKeepRates[domain] ?? 0.5 // Default moderate trust for known domains
    }

    private func contentDepthScore(item: Item) -> Double {
        let contentLength = (item.content?.count ?? 0) + item.title.count
        switch contentLength {
        case 0..<50: return 0.1
        case 50..<200: return 0.4
        case 200..<500: return 0.7
        default: return 1.0
        }
    }

    private func recencyScore(item: Item) -> Double {
        let publishedString = item.metadata["publishedAt"] ?? ""
        let publishDate: Date
        if !publishedString.isEmpty,
           let date = ISO8601DateFormatter().date(from: publishedString) {
            publishDate = date
        } else {
            publishDate = item.createdAt
        }

        let daysSince = Calendar.current.dateComponents([.day], from: publishDate, to: .now).day ?? 0
        switch daysSince {
        case 0...1: return 1.0
        case 2...3: return 0.8
        case 4...7: return 0.6
        case 8...14: return 0.3
        default: return 0.1
        }
    }

    private func boardAlignmentScore(item: Item, boardThemes: Set<String>) -> Double {
        guard !boardThemes.isEmpty else { return 0.3 }

        let keywords = extractKeywords(from: item)
        let overlap = keywords.intersection(boardThemes)
        return overlap.isEmpty ? 0.1 : min(1.0, Double(overlap.count) * 0.4)
    }

    // MARK: - Data Fetching

    private func fetchSuggestions(in context: ModelContext) -> [Item] {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return [] }
        return items.filter {
            $0.metadata["isSuggested"] == "true" &&
            $0.metadata["suggestionDismissed"] != "true"
        }
    }

    private func fetchUserTagVocabulary(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<Tag>()
        guard let tags = try? context.fetch(descriptor) else { return [] }
        return Set(tags.map { $0.name.lowercased() })
    }

    private func computeDomainKeepRates(in context: ModelContext) -> [String: Double] {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return [:] }

        let userItems = items.filter { $0.metadata["isSuggested"] != "true" }

        var domainCounts: [String: (total: Int, kept: Int)] = [:]
        for item in userItems {
            guard let domain = extractDomain(from: item) else { continue }
            var entry = domainCounts[domain] ?? (total: 0, kept: 0)
            entry.total += 1
            if item.status == .active || item.status == .queued {
                entry.kept += 1
            }
            domainCounts[domain] = entry
        }

        var rates: [String: Double] = [:]
        for (domain, counts) in domainCounts {
            rates[domain] = counts.total > 0 ? Double(counts.kept) / Double(counts.total) : 0.5
        }
        return rates
    }

    private func fetchBoardThemes(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<Board>()
        guard let boards = try? context.fetch(descriptor) else { return [] }
        var themes = Set<String>()
        for board in boards {
            let words = board.title.lowercased().split(separator: " ").map(String.init)
            themes.formUnion(words)
        }
        return themes
    }

    // MARK: - Helpers

    private func extractKeywords(from item: Item) -> Set<String> {
        let text = [item.title, item.content ?? ""].joined(separator: " ")
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 }
        return Set(words)
    }

    private func extractDomain(from item: Item) -> String? {
        if let domain = item.metadata["feedSourceDomain"] {
            return domain
        }
        guard let urlString = item.sourceURL,
              let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
