import Foundation
import SwiftData
import Testing
@testable import grove

/// The Following unread badge counts only issues the Following list can show,
/// and deleting a subscription leaves nothing behind that keeps counting.
@MainActor
struct FollowingUnreadTests {
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "FollowingUnreadTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func insertSource(_ name: String, in context: ModelContext) -> FeedSource {
        let source = FeedSource(feedURL: "https://\(name).example/feed", domain: "\(name).example", isUserSubscribed: true)
        context.insert(source)
        return source
    }

    /// An unread, unkept issue as feed ingest writes it.
    private func insertIssue(from source: FeedSource, in context: ModelContext) -> Item {
        let item = Item(title: "Issue", type: .article)
        item.feedSourceID = source.id.uuidString
        item.isFeedSuggestion = true
        context.insert(item)
        return item
    }

    @Test func orphanedIssuesInAnExistingStoreStopCounting() throws {
        let context = try makeInMemoryModelContext()
        let live = insertSource("live", in: context)
        let gone = insertSource("gone", in: context)
        _ = insertIssue(from: live, in: context)
        _ = insertIssue(from: gone, in: context)
        _ = insertIssue(from: gone, in: context)
        // An older build deleted the source and left its issues behind.
        context.delete(gone)
        try context.save()

        let items: [Item] = context.fetchAll()
        let sources: [FeedSource] = context.fetchAll()
        #expect(FeedSubscriptionService.unreadIssueCount(items: items, sources: sources) == 1)
    }

    @Test func readAndDismissedIssuesDoNotCount() throws {
        let context = try makeInMemoryModelContext()
        let source = insertSource("live", in: context)
        let read = insertIssue(from: source, in: context)
        read.isFeedIssueRead = true
        let dismissed = insertIssue(from: source, in: context)
        dismissed.status = .dismissed
        _ = insertIssue(from: source, in: context)
        let personal = Item(title: "Mine", type: .note)
        context.insert(personal)
        try context.save()

        let items: [Item] = context.fetchAll()
        #expect(FeedSubscriptionService.unreadIssueCount(items: items, sources: [source]) == 1)
    }

    @Test func deletingASubscriptionDismissesItsUnkeptIssuesOnly() throws {
        let context = try makeInMemoryModelContext()
        let source = insertSource("gone", in: context)
        let other = insertSource("other", in: context)
        let unread = insertIssue(from: source, in: context)
        let kept = insertIssue(from: source, in: context)
        kept.promoteFromFeedSuggestionIfNeeded()
        kept.isFeedIssueRead = false
        let otherIssue = insertIssue(from: other, in: context)
        try context.save()

        FeedSubscriptionService.delete(source, in: context)

        let sources: [FeedSource] = context.fetchAll()
        #expect(sources.map(\.id) == [other.id])
        #expect(unread.isFeedIssueRead)
        #expect(unread.isSuggestionDismissed)
        #expect(!kept.isFeedSuggestion)
        #expect(!kept.isFeedIssueRead)
        #expect(!kept.isSuggestionDismissed)
        #expect(kept.status == .active)
        #expect(!otherIssue.isFeedIssueRead)

        let items: [Item] = context.fetchAll()
        #expect(FeedSubscriptionService.unreadIssueCount(items: items, sources: sources) == 1)
    }
}
