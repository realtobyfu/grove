import Foundation
import SwiftData
import SwiftUI

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
}
