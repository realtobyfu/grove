import Foundation
import SwiftData

@Model
final class FeedSource {
    var id: UUID
    var feedURL: String
    var domain: String
    var title: String?
    var lastFetchedAt: Date?
    var isEnabled: Bool
    var isAutoDiscovered: Bool
    var errorCount: Int
    var createdAt: Date

    init(
        feedURL: String,
        domain: String,
        title: String? = nil,
        isAutoDiscovered: Bool = true
    ) {
        self.id = UUID()
        self.feedURL = feedURL
        self.domain = domain
        self.title = title
        self.lastFetchedAt = nil
        self.isEnabled = true
        self.isAutoDiscovered = isAutoDiscovered
        self.errorCount = 0
        self.createdAt = .now
    }
}
