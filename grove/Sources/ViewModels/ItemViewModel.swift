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
        if !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
            item.updatedAt = .now
            try? modelContext.save()
        }
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
                item.boards.append(board)
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

    func deleteItem(_ item: Item) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    // MARK: - Connections

    func createConnection(source: Item, target: Item, type: ConnectionType) -> Connection? {
        guard source.id != target.id else { return nil }
        let connection = Connection(sourceItem: source, targetItem: target, type: type)
        modelContext.insert(connection)
        source.outgoingConnections.append(connection)
        target.incomingConnections.append(connection)
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
