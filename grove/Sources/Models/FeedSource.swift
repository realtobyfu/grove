import Foundation
import SwiftData

@Model
final class FeedSource {
    var id: UUID = UUID()
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
    var createdAt: Date = Date.now

    init(
        feedURL: String,
        domain: String,
        title: String? = nil,
        isAutoDiscovered: Bool = true,
        isEnabled: Bool = true,
        isUserSubscribed: Bool = false
    ) {
        self.id = UUID()
        self.feedURL = feedURL
        self.domain = domain
        self.title = title
        self.lastFetchedAt = nil
        self.isEnabled = isEnabled
        self.isAutoDiscovered = isAutoDiscovered
        self.isUserSubscribed = isUserSubscribed
        self.errorCount = 0
        self.createdAt = .now
    }
}
