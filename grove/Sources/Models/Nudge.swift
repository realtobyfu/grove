import Foundation
import SwiftData

enum NudgeType: String, Codable {
    // Active engine categories.
    case resurface
    case staleInbox

    // Legacy categories retained for persisted-model compatibility.
    case connectionPrompt
    case streak
    case continueCourse

    // Legacy smart (LLM-generated) nudge categories.
    case reflectionPrompt
    case contradiction
    case knowledgeGap
    case synthesisPrompt

    // Legacy dialectical check-in nudge category.
    case dialecticalCheckIn
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
