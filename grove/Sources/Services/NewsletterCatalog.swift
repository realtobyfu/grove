import Foundation

// MARK: - Catalog Entry

/// One hand-curated newsletter in the bundled directory
/// (grove/Resources/NewsletterCatalog.json).
struct NewsletterCatalogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let feedURL: String
    let siteURL: String
    let topics: [String]
    let blurb: String

    /// Host of the newsletter's site, with a leading "www." stripped —
    /// matches the domain convention used by FeedSource.
    var domain: String {
        guard let host = URL(string: siteURL)?.host?.lowercased() else { return siteURL }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - Catalog Loader

enum NewsletterCatalog {
    /// All bundled catalog entries. Loaded once; empty if the resource is missing.
    static let entries: [NewsletterCatalogEntry] = load()

    private static func load() -> [NewsletterCatalogEntry] {
        guard let url = Bundle.main.url(forResource: "NewsletterCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([NewsletterCatalogEntry].self, from: data) else {
            return []
        }
        return entries
    }
}

// MARK: - Personalized Ranking

/// A catalog entry with a relevance score against the user's library and an
/// optional human-readable reason for a strong match.
struct RankedNewsletterEntry: Identifiable, Sendable {
    let entry: NewsletterCatalogEntry
    let score: Double
    /// Non-nil only for strong matches, e.g. "Because you save swift content".
    let reason: String?

    var id: String { entry.id }
}

/// Deterministic, on-device relevance ranking for the newsletter directory.
/// Primary signal is keyword overlap between an entry's topics/title/blurb and
/// the user's tags + recent item titles; an optional second pass adds sentence
/// embedding similarity via EmbeddingIndexService when available.
enum NewsletterRanker {
    /// Weighted user tag: name is lowercased, weight is the item count.
    struct UserTag: Sendable {
        let name: String
        let weight: Int
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "your", "into",
        "what", "when", "how", "why", "about", "on", "of", "in", "to", "a", "an"
    ]

    /// Synchronous keyword-overlap ranking. Deterministic: score descending,
    /// ties broken by title.
    static func rank(
        entries: [NewsletterCatalogEntry],
        userTags: [UserTag],
        recentTitles: [String]
    ) -> [RankedNewsletterEntry] {
        let tagTokens = userTags.map { (token: $0.name, weight: $0.weight) }
        let titleTokens = tokenSet(from: recentTitles.joined(separator: " "))

        let ranked = entries.map { entry -> RankedNewsletterEntry in
            var score = 0.0
            var bestMatch: (tag: String, weight: Int)?

            let entryTopics = Set(entry.topics.map { $0.lowercased() })
            let entryText = tokenSet(from: entry.title + " " + entry.blurb)

            for tag in tagTokens {
                let matchesTopic = entryTopics.contains { topic in
                    topic == tag.token || topic.contains(tag.token) || tag.token.contains(topic)
                }
                let matchesText = entryText.contains(tag.token)
                guard matchesTopic || matchesText else { continue }

                // Topic matches are the strongest signal; weight by how much
                // the user actually saves under that tag (capped).
                let weightBoost = Double(min(tag.weight, 5)) / 5.0
                score += (matchesTopic ? 2.0 : 0.75) * (0.5 + weightBoost)

                if matchesTopic, tag.weight >= (bestMatch?.weight ?? 3) {
                    bestMatch = (tag.token, tag.weight)
                }
            }

            // Light signal from recent item titles overlapping the entry text.
            let titleOverlap = entryText.intersection(titleTokens).count
            score += Double(min(titleOverlap, 4)) * 0.25

            let reason = bestMatch.map { "Because you save \($0.tag) content" }
            return RankedNewsletterEntry(entry: entry, score: score, reason: reason)
        }

        return sortDeterministically(ranked)
    }

    /// Optional refinement: adds cosine similarity between a user profile text
    /// (top tags + recent titles) and each entry's text, using the on-device
    /// sentence embedding. Falls back to the input ordering when no embedding
    /// is available for the profile's language.
    static func refine(
        _ ranked: [RankedNewsletterEntry],
        profileText: String
    ) async -> [RankedNewsletterEntry] {
        let trimmed = profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let profile = await EmbeddingIndexService.shared.embed(trimmed) else {
            return ranked
        }

        var refined: [RankedNewsletterEntry] = []
        for item in ranked {
            let text = "\(item.entry.title). \(item.entry.blurb) \(item.entry.topics.joined(separator: " "))"
            if let embedded = await EmbeddingIndexService.shared.embed(text),
               embedded.language == profile.language {
                let similarity = EmbeddingIndexService.cosineSimilarity(profile.vector, embedded.vector)
                refined.append(RankedNewsletterEntry(
                    entry: item.entry,
                    score: item.score + max(0, similarity) * 2.0,
                    reason: item.reason
                ))
            } else {
                refined.append(item)
            }
        }
        return sortDeterministically(refined)
    }

    // MARK: - Helpers

    private static func sortDeterministically(_ entries: [RankedNewsletterEntry]) -> [RankedNewsletterEntry] {
        entries.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.entry.title.localizedCaseInsensitiveCompare($1.entry.title) == .orderedAscending
        }
    }

    private static func tokenSet(from text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopwords.contains($0) }
        )
    }
}
