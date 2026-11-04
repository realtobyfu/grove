import Foundation
import SQLiteData

/// Deprecated in favour of `ReflectionBlock`, kept so old rows survive.
@Table("annotations")
struct Annotation: Hashable, Identifiable, Sendable {
    let id: UUID
    var itemID: Item.ID?
    var content: String = ""
    var highlight: String?
    var position: Int?
    var createdAt: Date = .now
}

