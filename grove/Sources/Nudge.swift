import Foundation
import SwiftData

enum NudgeType: String, Codable {
    case resurface
    case connectionPrompt
    case staleInbox
    case streak
}

enum NudgeStatus: String, Codable {
    case pending
    case shown
    case actedOn
    case dismissed
}

@Model
final class Nudge {
    var id: UUID
    var type: NudgeType
    var targetItem: Item?
    var relatedItemIDs: [UUID]?
    var message: String
    var status: NudgeStatus
    var scheduledFor: Date
    var createdAt: Date

    init(type: NudgeType, message: String, scheduledFor: Date = .now, targetItem: Item? = nil) {
        self.id = UUID()
        self.type = type
        self.targetItem = targetItem
        self.relatedItemIDs = nil
        self.message = message
        self.status = .pending
        self.scheduledFor = scheduledFor
        self.createdAt = .now
    }
}
