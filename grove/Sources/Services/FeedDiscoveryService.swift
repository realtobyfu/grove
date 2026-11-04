import Foundation
import SQLiteData

/// Takes the database per call rather than holding it: `shared` is created while
/// `GroveApp`'s properties initialize, before the database is set up.
@MainActor
@Observable
final class FeedDiscoveryService {
    static let shared = FeedDiscoveryService()

    private static let cooldownKey = "grove.feedDiscovery.lastRunAt"
    private static let cooldownInterval: TimeInterval = 24 * 60 * 60
    private static let maxDomainsPerCycle = 10
    private static let delayBetweenFetches: UInt64 = 1_000_000_000 // 1s

    private(set) var isRunning = false

    /// Domains already tried by the on-demand path this session. Inbox cards
    /// re-render constantly, so without this a single site would be fetched
    /// once per render pass. Deliberately in-memory: a relaunch is a cheap,
    /// user-invisible way to retry a site that was down.
    @ObservationIgnored
    private var attemptedDomains: Set<String> = []

    func discoverFeeds(database: any DatabaseWriter = AppDatabase.current) async {
        guard !isRunning else { return }
        guard !isInCooldown() else { return }

        isRunning = true
        defer {
            isRunning = false
            markCooldown()
        }

        let domains = extractDomains(from: database)
        let existingFeedURLs = existingFeedURLSet(from: database)

        var processed = 0
        for domain in domains {
            guard processed < Self.maxDomainsPerCycle else { break }

            if let feeds = await fetchFeedLinks(for: domain) {
                for feed in feeds
                where !existingFeedURLs.contains(feed.url)
                    && !FeedPreferencesStore.isDiscoveryDismissed(feed.url) {
                    // Discovered feeds are suggestions, not silent subscriptions:
                    // they stay disabled until the user subscribes in Settings.
                    let source = FeedSource(
                        feedURL: feed.url,
                        domain: domain,
                        title: feed.title,
                        isAutoDiscovered: true,
                        isEnabled: false
                    )
                    // Written as found, so the on-demand path below sees it
                    // during the sweep's waits instead of adding a duplicate.
                    database.attempt { db in try FeedSource.insert { source }.execute(db) }
                }
            }

            processed += 1
            if processed < domains.count {
                try? await Task.sleep(nanoseconds: Self.delayBetweenFetches)
            }
        }
    }

    // MARK: - On-Demand Single-Domain Discovery

    /// Looks up one site's advertised feed so the inbox can offer "+ Follow"
    /// while the user is still looking at the article.
    ///
    /// Unlike `discoverFeeds()` this ignores the 24h library-wide cooldown —
    /// it is scoped to a single domain the user just captured from — but each
    /// domain is only fetched once per app session. Inserts at most one
    /// suggestion, left disabled and unsubscribed like every auto-discovery.
    func discoverFeed(forDomain domain: String, database: any DatabaseWriter = AppDatabase.current) async {
        let host = normalizedDomain(domain)
        guard !host.isEmpty else { return }
        guard attemptedDomains.insert(host).inserted else { return }
        guard !hasFeedSource(forDomain: host, in: database) else { return }

        guard let feeds = await fetchFeedLinks(for: host) else { return }

        // The network hop is a suspension point: the library sweep or another
        // card may have inserted a source for this domain in the meantime.
        guard !hasFeedSource(forDomain: host, in: database) else { return }

        let existingFeedURLs = existingFeedURLSet(from: database)
        guard let best = feeds.first(where: { feed in
            !existingFeedURLs.contains(feed.url)
                && !FeedPreferencesStore.isDiscoveryDismissed(feed.url)
                // Comment feeds are advertised alongside the real one on most
                // blog engines and are never what someone means by "follow".
                && !feed.url.localizedCaseInsensitiveContains("comment")
        }) else { return }

        let source = FeedSource(
            feedURL: best.url,
            domain: host,
            title: best.title,
            isAutoDiscovered: true,
            isEnabled: false,
            isUserSubscribed: false
        )
        database.attempt { db in try FeedSource.insert { source }.execute(db) }
    }

    private func hasFeedSource(forDomain host: String, in database: any DatabaseWriter) -> Bool {
        guard let sources = database.attemptRead({ try FeedSource.all.fetchAll($0) }) else { return false }
        return sources.contains { normalizedDomain($0.domain) == host }
    }

    // MARK: - Domain Extraction

    private func extractDomains(from database: any DatabaseWriter) -> [String] {
        let items = database.attemptRead { db in
            try Item.where { $0.sourceURL.isNot(nil) }.fetchAll(db)
        } ?? []

        let articleItems = items.filter { $0.type == .article }
        var seen = Set<String>()
        var domains: [String] = []

        for item in articleItems {
            guard let urlString = item.sourceURL,
                  let url = URL(string: urlString),
                  let host = url.host?.lowercased() else { continue }

            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if seen.insert(domain).inserted {
                domains.append(domain)
            }
        }

        return domains
    }

    // MARK: - Existing Feed URLs

    private func existingFeedURLSet(from database: any DatabaseWriter) -> Set<String> {
        guard let sources = database.attemptRead({ try FeedSource.all.fetchAll($0) }) else { return [] }
        return Set(sources.map(\.feedURL))
    }

    // MARK: - HTML Fetching & Feed Link Parsing

    private struct DiscoveredFeed {
        let url: String
        let title: String?
    }

    private func fetchFeedLinks(for domain: String) async -> [DiscoveredFeed]? {
        guard let url = URL(string: "https://\(domain)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Grove/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseFeedLinks(from: html, baseURL: url)
    }

    private func parseFeedLinks(from html: String, baseURL: URL) -> [DiscoveredFeed] {
        var feeds: [DiscoveredFeed] = []

        // Match <link> tags with RSS or Atom types
        let pattern = #"<link[^>]*type\s*=\s*["'](application/rss\+xml|application/atom\+xml)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return feeds
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])

            guard let href = extractAttribute("href", from: tag) else { continue }
            let title = extractAttribute("title", from: tag)

            let resolvedURL: String
            if href.hasPrefix("http://") || href.hasPrefix("https://") {
                resolvedURL = href
            } else if href.hasPrefix("/") {
                resolvedURL = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + href
            } else {
                resolvedURL = baseURL.absoluteString + "/" + href
            }

            feeds.append(DiscoveredFeed(url: resolvedURL, title: title))
        }

        return feeds
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 2), in: tag) else {
            return nil
        }
        let value = String(tag[valueRange])
        return value.isEmpty ? nil : value
    }

    // MARK: - Cooldown

    private func isInCooldown() -> Bool {
        guard let lastRun = UserDefaults.standard.object(forKey: Self.cooldownKey) as? Date else {
            return false
        }
        return Date.now.timeIntervalSince(lastRun) < Self.cooldownInterval
    }

    private func markCooldown() {
        UserDefaults.standard.set(Date.now, forKey: Self.cooldownKey)
    }
}
