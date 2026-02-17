import Foundation
import SwiftData

@Model
final class Board {
    var id: UUID
    var title: String
    var boardDescription: String?
    var icon: String?
    var color: String?
    var createdAt: Date
    var sortOrder: Int
    var isSmart: Bool

    var items: [Item]

    init(title: String, icon: String? = nil, color: String? = nil) {
        self.id = UUID()
        self.title = title
        self.boardDescription = nil
        self.icon = icon
        self.color = color
        self.createdAt = .now
        self.sortOrder = 0
        self.isSmart = false
        self.items = []
    }
}
