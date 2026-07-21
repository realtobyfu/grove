import Foundation
import SwiftData

@MainActor
@Observable
final class FeedFetchService {
    static let shared = FeedFetchService()

    private static let refreshIntervalSeconds: TimeInterval = 4 * 60 * 60 // 4 hours
    private static let maxNewSuggestionsPerFeed = 3
    private static let maxNewItemsPerSubscribedFeed = 20
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

        var existingURLs = existingSuggestedURLs(in: context)
        var totalCreated = 0

        for source in sources {
            guard source.errorCount < Self.maxErrorCount else { continue }
            // The per-cycle cap only throttles auto-discovered suggestion
            // sources; user subscriptions always fetch.
            if !source.isUserSubscribed, totalCreated >= Self.maxNewSuggestionsPerCycle { continue }
            // lastFetchedAt syncs via CloudKit, so this also skips sources
            // another device fetched recently — fewer duplicate-item races.
            if let lastFetched = source.lastFetchedAt,
               Date.now.timeIntervalSince(lastFetched) < Self.refreshIntervalSeconds {
                continue
            }

            let created = await fetchFeed(source, existingURLs: &existingURLs, in: context)
            if !source.isUserSubscribed {
                totalCreated += created
            }
        }

        try? context.save()
    }

    private func fetchFeed(
        _ source: FeedSource,
        existingURLs: inout Set<String>,
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
            source.title = Self.extractFeedTitle(from: data)
        }

        let articles = FeedParserService.parse(data: data)
        var created = 0

        // Subscribed feeds keep their full recent history; auto-discovered
        // sources stay capped, and ones the user consistently dismisses
        // (and never keeps) are throttled to a single new suggestion per cycle.
        let perFeedCap = if source.isUserSubscribed {
            Self.maxNewItemsPerSubscribedFeed
        } else if FeedPreferencesStore.isThrottled(sourceID: source.id) {
            1
        } else {
            Self.maxNewSuggestionsPerFeed
        }

        for article in articles {
            guard created < perFeedCap else { break }
            // Match CaptureService's normalized dedupe so feed variants of an
            // already-saved article (e.g. ?utm_source=rss) don't slip through.
            guard !existingURLs.contains(CaptureService.normalizedURLString(article.url)) else { continue }

            let item = Item(title: article.title, type: .article)
            item.sourceURL = article.url
            item.status = .inbox
            // The feed description is an excerpt (often the issue's own
            // intro), not the article body: store it as list-preview summary
            // only. The reader loads the real page; promotion generates a
            // proper overview.
            if let description = article.description, !description.isEmpty {
                item.metadata["summary"] = String(description.prefix(200))
            }
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
            existingURLs.insert(CaptureService.normalizedURLString(article.url))
            created += 1
        }

        return created
    }

    // MARK: - Deduplication

    /// All source URLs already in the library. Built once per refresh cycle;
    /// URLs created during the cycle are appended by the caller.
    private func existingSuggestedURLs(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return [] }
        return Set(items.compactMap(\.sourceURL).map(CaptureService.normalizedURLString))
    }

    // MARK: - Expiration

    private func expireOldSuggestions(in context: ModelContext) {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.suggestionExpiryDays, to: .now) ?? .now

        for item in items {
            guard item.isFeedSuggestion,
                  item.createdAt < cutoff else { continue }
            if item.isNewsletterIssue {
                // Newsletter issues stay browsable as history in the
                // Newsletters section; expiry just clears their unread state.
                guard !item.isFeedIssueRead else { continue }
                item.isFeedIssueRead = true
            } else if item.metadata["suggestionDismissed"] != "true" {
                item.metadata["suggestionDismissed"] = "true"
                if item.status == .inbox {
                    // Archive rather than dismiss. Nothing in the app surfaces
                    // `.dismissed`, so dismissing here stranded expired items
                    // permanently out of reach; `.archived` keeps them
                    // browsable under Library's archived filter.
                    item.status = .archived
                }
            }
        }
    }

    // MARK: - Feed Title Extraction

    nonisolated static func extractFeedTitle(from data: Data) -> String? {
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
