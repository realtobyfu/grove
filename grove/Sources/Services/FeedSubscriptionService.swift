import Foundation
import SwiftData

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
            case .invalidURL: "Enter a valid http(s) feed URL."
            case .unreachable: "Couldn't reach that URL."
            case .notAFeed: "That URL doesn't look like an RSS or Atom feed."
            }
        }
    }

    /// Subscribes to an existing discovered/known source: enables it, marks it
    /// user-subscribed, and clears any prior error count.
    static func subscribe(_ source: FeedSource, in context: ModelContext) {
        source.isEnabled = true
        source.isUserSubscribed = true
        source.errorCount = 0
        try? context.save()
    }

    /// Subscribes by feed URL, reusing an existing source (matched on a
    /// normalized URL) or inserting a new one. Returns the resulting source.
    @discardableResult
    static func subscribe(
        feedURL: String,
        domain: String? = nil,
        title: String? = nil,
        in context: ModelContext
    ) -> FeedSource {
        let normalized = CaptureService.normalizedURLString(feedURL)
        let existing = (try? context.fetch(FetchDescriptor<FeedSource>()))?
            .first { CaptureService.normalizedURLString($0.feedURL) == normalized }

        if let existing {
            if let title, existing.title == nil { existing.title = title }
            subscribe(existing, in: context)
            return existing
        }

        let source = FeedSource(
            feedURL: feedURL,
            domain: domain ?? domainFrom(feedURL),
            title: title,
            isAutoDiscovered: false,
            isEnabled: true,
            isUserSubscribed: true
        )
        context.insert(source)
        try? context.save()
        return source
    }

    /// Validates a user-entered feed URL (fetch + parse) and subscribes on
    /// success. Network + parsing live here rather than in the view.
    static func validateAndAdd(urlString: String, in context: ModelContext) async -> Result<FeedSource, AddFeedError> {
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
            return .failure(.notAFeed)
        }

        let source = subscribe(
            feedURL: url.absoluteString,
            domain: domainFrom(url.absoluteString),
            title: FeedFetchService.extractFeedTitle(from: data),
            in: context
        )
        return .success(source)
    }
}
