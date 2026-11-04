import Foundation
import SQLiteData

@Table("feedSources")
struct FeedSource: Hashable, Identifiable, Sendable {
    let id: UUID
    var feedURL: String = ""
    var domain: String = ""
    var title: String?
    var lastFetchedAt: Date?
    var isEnabled: Bool = false
    var isAutoDiscovered: Bool = false
    /// Whether the user has ever explicitly subscribed to this feed. Distinct
    /// from `isEnabled` (currently fetching) so toggling a subscription off
    /// keeps it in the Subscriptions list instead of teleporting it back to
    /// "Suggested from your library".
    var isUserSubscribed: Bool = false
    var errorCount: Int = 0
    var createdAt: Date = .now
}

extension FeedSource {
    init(
        feedURL: String,
        domain: String,
        title: String? = nil,
        isAutoDiscovered: Bool = true,
        isEnabled: Bool = true,
        isUserSubscribed: Bool = false
    ) {
        self.init(
            id: UUID(),
            feedURL: feedURL,
            domain: domain,
            title: title,
            isEnabled: isEnabled,
            isAutoDiscovered: isAutoDiscovered,
            isUserSubscribed: isUserSubscribed
        )
    }
}

