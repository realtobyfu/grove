import Foundation
import SwiftData

@Model
final class Annotation {
    var id: UUID
    var item: Item?
    var content: String
    var highlight: String?
    var position: Int?
    var createdAt: Date

    init(item: Item, content: String, highlight: String? = nil, position: Int? = nil) {
        self.id = UUID()
        self.item = item
        self.content = content
        self.highlight = highlight
        self.position = position
        self.createdAt = .now
    }
}
