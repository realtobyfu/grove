import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ItemViewModel {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createNote(title: String = "Untitled Note") -> Item {
        let item = Item(title: title, type: .note)
        item.status = .active
        modelContext.insert(item)
        try? modelContext.save()
        return item
    }

    func assignToBoard(_ item: Item, board: Board) {
        if !board.isSmart,
           !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
        }
        item.promoteFromFeedSuggestionIfNeeded()
        item.status = .active
        item.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: - Board Suggestions

    /// Files the item behind an accepted board suggestion. Takes the item's ID
    /// because the capture bars clear their pending suggestion on dismissal,
    /// which happens before this runs.
    func assignPendingItem(_ itemID: UUID, accepting decision: BoardSuggestionDecision) {
        let boards = (try? modelContext.fetch(FetchDescriptor<Board>())) ?? []
        if decision.mode == .existing,
           let recommended = boards.first(where: { $0.id == decision.recommendedBoardID }) {
            assignPendingItem(itemID, to: recommended)
        } else {
            let suggestedName = BoardSuggestionEngine.cleanedBoardName(decision.suggestedName)
            assignPendingItem(itemID, toBoardNamed: suggestedName.isEmpty ? "General" : suggestedName)
        }
    }

    func assignPendingItem(_ itemID: UUID, to board: Board) {
        guard let item = fetchItem(itemID) else { return }

        BoardSuggestionMetadata.recordSelection(board, on: item)
        assignToBoard(item, board: board)
    }

    /// Reuses a board with this title, or creates one. The item is checked
    /// first so a suggestion for a deleted item leaves no empty board behind.
    func assignPendingItem(_ itemID: UUID, toBoardNamed name: String) {
        let title = BoardSuggestionEngine.cleanedBoardName(name)
        guard !title.isEmpty, let item = fetchItem(itemID) else { return }

        let boards = (try? modelContext.fetch(FetchDescriptor<Board>())) ?? []
        let board: Board
        if let existing = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            board = existing
        } else {
            board = Board(title: title)
            modelContext.insert(board)
        }

        BoardSuggestionMetadata.recordSelection(board, on: item)
        assignToBoard(item, board: board)
    }

    private func fetchItem(_ itemID: UUID) -> Item? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        return try? modelContext.fetch(descriptor).first
    }

    func removeFromBoard(_ item: Item, board: Board) {
        item.boards.removeAll { $0.id == board.id }
        item.updatedAt = .now
        try? modelContext.save()
    }

    func moveItemsToBoard(_ items: [Item], board: Board?) {
        for item in items {
            item.boards.removeAll()
            if let board {
                if !board.isSmart {
                    item.boards.append(board)
                }
                item.status = .active
            }
            item.updatedAt = .now
        }
        try? modelContext.save()
    }

    func updateItem(_ item: Item, title: String, content: String?) {
        item.title = title
        item.content = content
        item.updatedAt = .now
        try? modelContext.save()
    }

    /// The single UI-facing deletion path for `Item`. Views must never call
    /// `modelContext.delete(_:)` on an Item directly: presentation layers hold
    /// strong references to the model (write panel, reader, inspector,
    /// selection) and only find out through `.groveItemWillDelete`.
    ///
    /// The notification is posted *before* the delete so observers can read
    /// `item.id` and tear down while the model is still valid.
    func deleteItem(_ item: Item) {
        retireItem(item)
        modelContext.delete(item)
        try? modelContext.save()
    }

    /// Bulk variant of `deleteItem(_:)` — announces every item before deleting,
    /// then saves once.
    func deleteItems(_ items: [Item]) {
        guard !items.isEmpty else { return }
        for item in items {
            retireItem(item)
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    /// Everything a deletion owes the rest of the app, in the moment the model
    /// is still valid: announce it, then drop the on-disk caches keyed by its
    /// id. Those caches (the Reader-mode extraction, the downloaded PDF) are
    /// outside SwiftData, so nothing else will ever collect them.
    private func retireItem(_ item: Item) {
        let id = item.id
        NotificationCenter.default.postItemWillDelete(id: id)
        ArticleReaderService.shared.removeCachedArticle(for: id)
        PDFMetadataService.removeCachedFile(itemID: id)
    }

    // MARK: - Connections

    func createConnection(source: Item, target: Item, type: ConnectionType) -> Connection? {
        guard source.id != target.id else { return nil }
        let connection = Connection(sourceItem: source, targetItem: target, type: type)
        modelContext.insert(connection)
        source.outgoingConnections.append(connection)
        target.incomingConnections.append(connection)
        source.promoteFromFeedSuggestionIfNeeded()
        target.promoteFromFeedSuggestionIfNeeded()
        source.updatedAt = .now
        target.updatedAt = .now
        try? modelContext.save()
        return connection
    }

    func deleteConnection(_ connection: Connection) {
        if let source = connection.sourceItem {
            source.outgoingConnections.removeAll { $0.id == connection.id }
            source.updatedAt = .now
        }
        if let target = connection.targetItem {
            target.incomingConnections.removeAll { $0.id == connection.id }
            target.updatedAt = .now
        }
        modelContext.delete(connection)
        try? modelContext.save()
    }

    /// Find items matching a search query (for fuzzy-search in connection/wiki-link pickers)
    func searchItems(query: String, excluding: Item? = nil) -> [Item] {
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return [] }
        let filtered = allItems.filter { item in
            if let excluding, item.id == excluding.id { return false }
            if query.isEmpty { return true }
            return item.title.localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.prefix(20))
    }
}
