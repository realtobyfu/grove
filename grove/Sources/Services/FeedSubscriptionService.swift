import Foundation
import SQLiteData

/// Centralizes newsletter/RSS subscription mutations so the two entry points
/// (SubscriptionsSettingsView and NewsletterDirectoryView) share one dedupe and
/// subscribe rule instead of hand-rolling it each. Feed URLs are matched with
/// the same normalization CaptureService uses for item URLs.
@MainActor
enum FeedSubscriptionService {
    enum AddFeedError: LocalizedError {
        case invalidURL
        case unreachable
        case notAFeed

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter a valid http(s) URL."
            case .unreachable: "Couldn't reach that URL."
            case .notAFeed: "Couldn't find a feed at that site. Try pasting its RSS or Atom URL directly."
            }
        }
    }

    /// Subscribes to an existing discovered/known source: enables it, marks it
    /// user-subscribed, and clears any prior error count.
    static func subscribe(_ sourceID: FeedSource.ID, database: any DatabaseWriter = AppDatabase.current) {
        database.attempt { db in
            try FeedSource.modify(sourceID, in: db) { markSubscribed(&$0) }
        }
    }

    private static func markSubscribed(_ source: inout FeedSource) {
        source.isEnabled = true
        source.isUserSubscribed = true
        source.errorCount = 0
    }

    /// Subscribes by feed URL, reusing an existing source (matched on a
    /// normalized URL) or inserting a new one. Returns the resulting source.
    @discardableResult
    static func subscribe(
        feedURL: String,
        domain: String? = nil,
        title: String? = nil,
        database: any DatabaseWriter = AppDatabase.current
    ) -> FeedSource {
        let normalized = CaptureService.normalizedURLString(feedURL)
        let source = FeedSource(
            feedURL: feedURL,
            domain: domain ?? domainFrom(feedURL),
            title: title,
            isAutoDiscovered: false,
            isEnabled: true,
            isUserSubscribed: true
        )

        let saved = database.attempt { db -> FeedSource? in
            let existing = try FeedSource.all.fetchAll(db)
                .first { CaptureService.normalizedURLString($0.feedURL) == normalized }

            if let existing {
                return try FeedSource.modify(existing.id, in: db) { row in
                    if let title, row.title == nil { row.title = title }
                    markSubscribed(&row)
                }
            }

            try FeedSource.insert { source }.execute(db)
            return source
        }
        return (saved ?? nil) ?? source
    }

    /// Validates a user-entered feed URL (fetch + parse) and subscribes on
    /// success. Network + parsing live here rather than in the view.
    static func validateAndAdd(
        urlString: String,
        database: any DatabaseWriter = AppDatabase.current
    ) async -> Result<FeedSource, AddFeedError> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Grove/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return .failure(.unreachable)
        }

        guard !FeedParserService.parse(data: data).isEmpty else {
            // Not a feed — likely a blog or site homepage. Following someone's
            // blog by pasting its plain URL is the common case, so discover the
            // site's feed instead of rejecting.
            return await addByDiscoveringFeed(fromPage: data, pageURL: url, database: database)
        }

        let source = subscribe(
            feedURL: url.absoluteString,
            domain: domainFrom(url.absoluteString),
            title: FeedFetchService.extractFeedTitle(from: data),
            database: database
        )
        return .success(source)
    }

    // MARK: - Feed Discovery From a Site URL

    /// Tries the page's advertised `<link rel="alternate">` feeds first, then
    /// well-known feed paths on the site root. Subscribes to the first URL that
    /// actually parses as a feed.
    private static func addByDiscoveringFeed(
        fromPage data: Data,
        pageURL: URL,
        database: any DatabaseWriter
    ) async -> Result<FeedSource, AddFeedError> {
        var candidates: [String] = []

        if let html = String(data: data, encoding: .utf8) {
            candidates += advertisedFeedURLs(in: html, baseURL: pageURL)
        }

        if let scheme = pageURL.scheme, let host = pageURL.host {
            let root = "\(scheme)://\(host)"
            for path in ["/feed", "/feed.xml", "/rss", "/rss.xml", "/atom.xml", "/index.xml"] {
                candidates.append(root + path)
            }
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard let url = URL(string: candidate) else { continue }

            var request = URLRequest(url: url)
            request.setValue("Grove/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            guard let (feedData, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  !FeedParserService.parse(data: feedData).isEmpty else {
                continue
            }

            let source = subscribe(
                feedURL: url.absoluteString,
                domain: domainFrom(pageURL.absoluteString),
                title: FeedFetchService.extractFeedTitle(from: feedData),
                database: database
            )
            return .success(source)
        }

        return .failure(.notAFeed)
    }

    /// RSS/Atom `<link>` hrefs advertised in a page's HTML, resolved against
    /// the page URL, in document order.
    private static func advertisedFeedURLs(in html: String, baseURL: URL) -> [String] {
        let pattern = #"<link[^>]*type\s*=\s*["'](?:application/rss\+xml|application/atom\+xml)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else { return nil }
            let tag = String(html[matchRange])

            let hrefPattern = #"href\s*=\s*["']([^"']+)["']"#
            guard let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive),
                  let hrefMatch = hrefRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: tag) else {
                return nil
            }

            return URL(string: String(tag[hrefRange]), relativeTo: baseURL)?.absoluteString
        }
    }
}
