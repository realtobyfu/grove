import Foundation
import SQLiteData
import SwiftUI

@MainActor
@Observable
final class ItemViewModel {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
    }

    func createNote(title: String = "Untitled Note") -> Item {
        var note = Item(title: title, type: .note)
        note.status = .active
        let item = note
        database.attempt { db in
            try Item.insert { item }.execute(db)
        }
        return item
    }

    /// An item is on at most one board, so this moves it off any other.
    func assignToBoard(_ itemID: Item.ID, board: Board) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { item in
                if !board.isSmart {
                    item.boardID = board.id
                }
                item.promoteFromFeedSuggestionIfNeeded()
                item.status = .active
                item.updatedAt = .now
            }
        }
    }

    func removeFromBoard(_ itemID: Item.ID, boardID: Board.ID) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { item in
                guard item.boardID == boardID else { return }
                item.boardID = nil
                item.updatedAt = .now
            }
        }
    }

    func moveItemsToBoard(_ itemIDs: [Item.ID], board: Board?) {
        database.attempt { db in
            for itemID in itemIDs {
                try Item.modify(itemID, in: db) { item in
                    item.boardID = nil
                    if let board {
                        if !board.isSmart {
                            item.boardID = board.id
                        }
                        item.status = .active
                    }
                    item.updatedAt = .now
                }
            }
        }
    }

    func updateItem(_ itemID: Item.ID, title: String, content: String?) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { item in
                item.title = title
                item.content = content
                item.updatedAt = .now
            }
        }
    }

    /// The single UI-facing deletion path for `Item`. Views must never delete an
    /// Item directly: presentation layers hold on to it (write panel, reader,
    /// inspector, selection) and only find out through `.groveItemWillDelete`.
    ///
    /// The notification is posted *before* the delete so observers can tear down
    /// while the row still exists.
    func deleteItem(_ itemID: Item.ID) {
        deleteItems([itemID])
    }

    /// Bulk variant of `deleteItem(_:)` — announces every item before deleting,
    /// then deletes them in one transaction.
    func deleteItems(_ itemIDs: [Item.ID]) {
        guard !itemIDs.isEmpty else { return }
        for itemID in itemIDs {
            retireItem(itemID)
        }
        database.attempt { db in
            try Item.where { $0.id.in(itemIDs) }.delete().execute(db)
        }
    }

    /// Everything a deletion owes the rest of the app, in the moment the row
    /// still exists: announce it, then drop the on-disk caches keyed by its id.
    /// Those caches (the Reader-mode extraction, the downloaded PDF) are outside
    /// the database, so nothing else will ever collect them.
    private func retireItem(_ itemID: Item.ID) {
        NotificationCenter.default.postItemWillDelete(id: itemID)
        ArticleReaderService.shared.removeCachedArticle(for: itemID)
        PDFMetadataService.removeCachedFile(itemID: itemID)
    }

    // MARK: - Connections

    @discardableResult
    func createConnection(sourceID: Item.ID, targetID: Item.ID, type: ConnectionType) -> Connection? {
        guard sourceID != targetID else { return nil }
        let connection = Connection(sourceItemID: sourceID, targetItemID: targetID, type: type)
        let saved: Void? = database.attempt { db in
            try Connection.insert { connection }.execute(db)
            for itemID in [sourceID, targetID] {
                try Item.modify(itemID, in: db) { item in
                    item.promoteFromFeedSuggestionIfNeeded()
                    item.updatedAt = .now
                }
            }
        }
        return saved == nil ? nil : connection
    }

    func deleteConnection(_ connection: Connection) {
        database.attempt { db in
            try Connection.find(connection.id).delete().execute(db)
            for itemID in [connection.sourceItemID, connection.targetItemID].compactMap(\.self) {
                try Item.modify(itemID, in: db) { $0.updatedAt = .now }
            }
        }
    }

    /// Find items matching a search query (for fuzzy-search in connection/wiki-link pickers)
    func searchItems(query: String, excluding excludedID: Item.ID? = nil) -> [Item] {
        guard let allItems = database.attemptRead({ try Item.all.fetchAll($0) }) else { return [] }
        let filtered = allItems.filter { item in
            if item.id == excludedID { return false }
            if query.isEmpty { return true }
            return item.title.localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.prefix(20))
    }
}
