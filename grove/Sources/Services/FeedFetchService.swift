import Foundation
import SQLiteData

/// Takes the database per call rather than holding it: `shared` is created while
/// `GroveApp`'s properties initialize, before the database is set up.
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

    func refreshIfNeeded(database: any DatabaseWriter = AppDatabase.current) async {
        guard !isRefreshing else { return }
        if let last = lastRefreshAt,
           Date.now.timeIntervalSince(last) < Self.refreshIntervalSeconds {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        expireOldSuggestions(in: database)
        await fetchAllFeeds(in: database)
        lastRefreshAt = .now
    }

    /// Fetches a single source immediately, bypassing the refresh-interval
    /// throttle. Used right after the user subscribes so the feed's first
    /// posts appear without waiting for the next background cycle.
    func fetchNow(_ sourceID: FeedSource.ID, database: any DatabaseWriter = AppDatabase.current) async {
        guard let source = database.attemptRead({ try FeedSource.find(sourceID).fetchOne($0) }) ?? nil else { return }
        var existingURLs = existingSuggestedURLs(in: database)
        _ = await fetchFeed(source, existingURLs: &existingURLs, in: database)
    }

    // MARK: - Fetch All Feeds

    private func fetchAllFeeds(in database: any DatabaseWriter) async {
        guard let sources = database.attemptRead({ db in
            try FeedSource.where { $0.isEnabled }.fetchAll(db)
        }) else { return }

        var existingURLs = existingSuggestedURLs(in: database)
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

            let created = await fetchFeed(source, existingURLs: &existingURLs, in: database)
            if !source.isUserSubscribed {
                totalCreated += created
            }
        }
    }

    private func fetchFeed(
        _ source: FeedSource,
        existingURLs: inout Set<String>,
        in database: any DatabaseWriter
    ) async -> Int {
        guard let url = URL(string: source.feedURL) else {
            recordFailure(source.id, in: database)
            return 0
        }

        var request = URLRequest(url: url)
        request.setValue("Grove/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            recordFailure(source.id, in: database)
            return 0
        }

        let articles = FeedParserService.parse(data: data)
        var newItems: [Item] = []
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

            var item = Item(title: article.title, type: .article)
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

            newItems.append(item)
            existingURLs.insert(CaptureService.normalizedURLString(article.url))
            created += 1
        }

        // The fetch was a suspension point, so `source` may be out of date: only
        // what this fetch learned is written, onto the row as it stands now.
        database.attempt { db in
            try FeedSource.modify(source.id, in: db) { source in
                // Reset error count on success
                source.errorCount = 0
                source.lastFetchedAt = .now

                // Update feed title if we don't have one yet
                if source.title == nil {
                    source.title = Self.extractFeedTitle(from: data)
                }
            }
            for item in newItems {
                try Item.insert { item }.execute(db)
            }
        }

        return created
    }

    private func recordFailure(_ sourceID: FeedSource.ID, in database: any DatabaseWriter) {
        database.attempt { db in
            try FeedSource.modify(sourceID, in: db) { $0.errorCount += 1 }
        }
    }

    // MARK: - Deduplication

    /// All source URLs already in the library. Built once per refresh cycle;
    /// URLs created during the cycle are appended by the caller.
    private func existingSuggestedURLs(in database: any DatabaseWriter) -> Set<String> {
        guard let items = database.attemptRead({ try Item.all.fetchAll($0) }) else { return [] }
        return Set(items.compactMap(\.sourceURL).map(CaptureService.normalizedURLString))
    }

    // MARK: - Expiration

    private func expireOldSuggestions(in database: any DatabaseWriter) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.suggestionExpiryDays, to: .now) ?? .now

        database.attempt { db in
            for item in try Item.all.fetchAll(db) {
                guard item.isFeedSuggestion,
                      item.createdAt < cutoff else { continue }
                if item.isNewsletterIssue {
                    // Newsletter issues stay browsable as history in the
                    // Newsletters section; expiry just clears their unread state.
                    guard !item.isFeedIssueRead else { continue }
                    try Item.modify(item.id, in: db) { $0.isFeedIssueRead = true }
                } else if item.metadata["suggestionDismissed"] != "true" {
                    try Item.modify(item.id, in: db) { item in
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
