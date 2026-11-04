import Foundation
import SQLiteData

/// One-time repair for feed suggestions stranded by the core-loop overhaul.
///
/// Two things went wrong for items captured before the newsletter split:
///
/// 1. Every surface now hides `isFeedSuggestion` items, so feed-captured
///    articles that used to sit in the Library silently vanished from it —
///    including ones the user had reflected on or filed onto a board.
/// 2. Suggestion expiry moved unread items to `.dismissed`, a status no view
///    ever displays, making them unreachable rather than merely quiet.
///
/// This applies the app's existing "writing is keeping" rule retroactively and
/// lifts stranded items back into the archive, where they can be browsed.
@MainActor
final class FeedSuggestionMigrationService {
    private static let migratedKey = "grove.feedSuggestionsRepaired"

    static var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: migratedKey)
    }

    @discardableResult
    static func migrateIfNeeded(
        database: any DatabaseWriter = AppDatabase.current
    ) -> (promoted: Int, unstranded: Int) {
        guard !hasMigrated else { return (0, 0) }

        let counts = database.attempt { db -> (promoted: Int, unstranded: Int) in
            let items = try Library.fetch(db).items
            let annotatedItemIDs = Set(try Annotation.all.fetchAll(db).compactMap(\.itemID))

            var promoted = 0
            var unstranded = 0

            for item in items {
                // Rescue anything expiry pushed into the invisible `.dismissed`
                // state. Only feed suggestions dismissed by the expiry sweep are
                // touched — items the user dismissed by hand stay dismissed.
                if item.isFeedSuggestion,
                   item.status == .dismissed,
                   item.metadata["suggestionDismissed"] == "true" {
                    try Item.modify(item.id, in: db) { $0.status = .archived }
                    unstranded += 1
                }

                // A durable artifact means the user already kept this, whether or
                // not the capture path marked it as such at the time.
                guard item.isFeedSuggestion,
                      hasDurableArtifact(item, annotatedItemIDs: annotatedItemIDs) else { continue }
                try Item.modify(item.id, in: db) { $0.promoteFromFeedSuggestionIfNeeded() }
                promoted += 1
            }

            return (promoted, unstranded)
        }
        guard let counts else { return (0, 0) }

        UserDefaults.standard.set(true, forKey: migratedKey)
        return counts
    }

    /// Mirrors `Item.promoteFromFeedSuggestionIfNeeded`'s notion of keeping:
    /// a reflection, highlight, board assignment, or connection.
    private static func hasDurableArtifact(_ item: ItemGraph, annotatedItemIDs: Set<Item.ID>) -> Bool {
        !item.reflections.isEmpty
            || annotatedItemIDs.contains(item.id)
            || item.boardID != nil
            || !item.outgoingConnections.isEmpty
            || !item.incomingConnections.isEmpty
    }
}
