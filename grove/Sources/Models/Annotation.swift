import Foundation
import SwiftData

// DEPRECATED: migrated to ReflectionBlock. Kept in schema for SwiftData compatibility.
@Model
final class Annotation {
    var id: UUID = UUID()
    var item: Item?
    var content: String = ""
    var highlight: String?
    var position: Int?
    var createdAt: Date = Date.now

    init(item: Item, content: String, highlight: String? = nil, position: Int? = nil) {
        self.id = UUID()
        self.item = item
        self.content = content
        self.highlight = highlight
        self.position = position
        self.createdAt = .now
    }
}
