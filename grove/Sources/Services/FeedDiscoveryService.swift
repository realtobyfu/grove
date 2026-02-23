import Foundation
import SwiftData

@MainActor
@Observable
final class FeedDiscoveryService {
    static let shared = FeedDiscoveryService()

    private static let cooldownKey = "grove.feedDiscovery.lastRunAt"
    private static let cooldownInterval: TimeInterval = 24 * 60 * 60
    private static let maxDomainsPerCycle = 10
    private static let delayBetweenFetches: UInt64 = 1_000_000_000 // 1s

    private(set) var isRunning = false

    func discoverFeeds(in context: ModelContext) async {
        guard !isRunning else { return }
        guard !isInCooldown() else { return }

        isRunning = true
        defer {
            isRunning = false
            markCooldown()
        }

        let domains = extractDomains(from: context)
        let existingFeedURLs = existingFeedURLSet(from: context)

        var processed = 0
        for domain in domains {
            guard processed < Self.maxDomainsPerCycle else { break }

            if let feeds = await fetchFeedLinks(for: domain) {
                for feed in feeds where !existingFeedURLs.contains(feed.url) {
                    let source = FeedSource(
                        feedURL: feed.url,
                        domain: domain,
                        title: feed.title
                    )
                    context.insert(source)
                }
            }

            processed += 1
            if processed < domains.count {
                try? await Task.sleep(nanoseconds: Self.delayBetweenFetches)
            }
        }

        try? context.save()
    }

    // MARK: - Domain Extraction

    private func extractDomains(from context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<Item>()
        descriptor.predicate = #Predicate<Item> { item in
            item.sourceURL != nil
        }
        guard let items = try? context.fetch(descriptor) else { return [] }

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

    private func existingFeedURLSet(from context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<FeedSource>()
        guard let sources = try? context.fetch(descriptor) else { return [] }
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
