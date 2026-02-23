import Foundation
import SwiftData

@MainActor
@Observable
final class FeedFetchService {
    static let shared = FeedFetchService()

    private static let refreshIntervalSeconds: TimeInterval = 4 * 60 * 60 // 4 hours
    private static let maxNewSuggestionsPerFeed = 3
    private static let maxNewSuggestionsPerCycle = 20
    private static let maxErrorCount = 5
    private static let suggestionExpiryDays = 14

    private(set) var isRefreshing = false
    private var lastRefreshAt: Date?

    func refreshIfNeeded(in context: ModelContext) async {
        guard !isRefreshing else { return }
        if let last = lastRefreshAt,
           Date.now.timeIntervalSince(last) < Self.refreshIntervalSeconds {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        expireOldSuggestions(in: context)
        await fetchAllFeeds(in: context)
        lastRefreshAt = .now
    }

    // MARK: - Fetch All Feeds

    private func fetchAllFeeds(in context: ModelContext) async {
        var descriptor = FetchDescriptor<FeedSource>()
        descriptor.predicate = #Predicate<FeedSource> { source in
            source.isEnabled == true
        }
        guard let sources = try? context.fetch(descriptor) else { return }

        let existingURLs = existingSuggestedURLs(in: context)
        var totalCreated = 0

        for source in sources {
            guard source.errorCount < Self.maxErrorCount else { continue }
            guard totalCreated < Self.maxNewSuggestionsPerCycle else { break }

            let created = await fetchFeed(source, existingURLs: existingURLs, in: context)
            totalCreated += created
        }

        try? context.save()
    }

    private func fetchFeed(
        _ source: FeedSource,
        existingURLs: Set<String>,
        in context: ModelContext
    ) async -> Int {
        guard let url = URL(string: source.feedURL) else {
            source.errorCount += 1
            return 0
        }

        var request = URLRequest(url: url)
        request.setValue("Grove/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            source.errorCount += 1
            return 0
        }

        // Reset error count on success
        source.errorCount = 0
        source.lastFetchedAt = .now

        // Update feed title if we don't have one yet
        if source.title == nil {
            source.title = extractFeedTitle(from: data)
        }

        let articles = FeedParserService.parse(data: data)
        var created = 0

        for article in articles {
            guard created < Self.maxNewSuggestionsPerFeed else { break }
            guard !existingURLs.contains(article.url) else { continue }
            guard !isDuplicate(url: article.url, in: context) else { continue }

            let item = Item(title: article.title, type: .article)
            item.sourceURL = article.url
            item.status = .inbox
            item.content = article.description
            item.metadata["isSuggested"] = "true"
            item.metadata["suggestionSource"] = "rss"
            item.metadata["feedSourceID"] = source.id.uuidString
            item.metadata["feedSourceDomain"] = source.domain
            if let pubDate = article.publishedAt {
                item.metadata["publishedAt"] = ISO8601DateFormatter().string(from: pubDate)
            }
            if let author = article.author {
                item.metadata["author"] = author
            }

            context.insert(item)
            created += 1
        }

        return created
    }

    // MARK: - Deduplication

    private func existingSuggestedURLs(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return [] }
        return Set(items.compactMap(\.sourceURL))
    }

    private func isDuplicate(url: String, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return false }
        return items.contains { $0.sourceURL == url }
    }

    // MARK: - Expiration

    private func expireOldSuggestions(in context: ModelContext) {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.suggestionExpiryDays, to: .now) ?? .now

        for item in items {
            guard item.metadata["isSuggested"] == "true",
                  item.metadata["suggestionDismissed"] != "true",
                  item.createdAt < cutoff else { continue }
            item.metadata["suggestionDismissed"] = "true"
        }
    }

    // MARK: - Feed Title Extraction

    private func extractFeedTitle(from data: Data) -> String? {
        // Simple extraction: parse as feed and grab the first non-item title
        // This is a lightweight approach; FeedParserService focuses on items
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"<title[^>]*>([^<]+)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(xmlString.startIndex..., in: xmlString)
        guard let match = regex.firstMatch(in: xmlString, range: range),
              let titleRange = Range(match.range(at: 1), in: xmlString) else { return nil }
        let title = String(xmlString[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
