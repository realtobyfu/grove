import Foundation
import SwiftData

enum ItemType: String, Codable {
    case article
    case video
    case note
    case courseLecture
}

enum ItemStatus: String, Codable {
    case inbox
    case active
    case archived
    case dismissed
}

@Model
final class Item {
    var id: UUID
    var title: String
    var type: ItemType
    var status: ItemStatus
    var sourceURL: String?
    var content: String?
    var thumbnail: Data?
    var engagementScore: Float
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \Board.items) var boards: [Board]
    @Relationship(inverse: \Tag.items) var tags: [Tag]
    @Relationship(deleteRule: .cascade, inverse: \Annotation.item) var annotations: [Annotation]
    @Relationship(deleteRule: .cascade, inverse: \Connection.sourceItem) var outgoingConnections: [Connection]
    @Relationship(deleteRule: .cascade, inverse: \Connection.targetItem) var incomingConnections: [Connection]

    init(title: String, type: ItemType) {
        self.id = UUID()
        self.title = title
        self.type = type
        self.status = .inbox
        self.sourceURL = nil
        self.content = nil
        self.thumbnail = nil
        self.engagementScore = 0
        self.metadata = [:]
        self.createdAt = .now
        self.updatedAt = .now
        self.boards = []
        self.tags = []
        self.annotations = []
        self.outgoingConnections = []
        self.incomingConnections = []
    }
}
