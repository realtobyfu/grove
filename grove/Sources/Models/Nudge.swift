import Foundation
import SwiftData

/// Raw values are persisted in `Nudge.type`, so every case stays even though
/// no generator is left; persisted records still decode.
enum NudgeType: String, Codable {
    case staleInbox
    case resurface
    case connectionPrompt
    case streak
    case continueCourse
    case reflectionPrompt
    case contradiction
    case knowledgeGap
    case synthesisPrompt
    case dialecticalCheckIn
}

enum NudgeStatus: String, Codable {
    case pending
    case shown
    case actedOn
    case dismissed
}

/// Retired: nothing creates or reads nudges; the model stays only for the synced schema.
@Model
final class Nudge {
    var id: UUID = UUID()
    var type: NudgeType = NudgeType.resurface
    var targetItem: Item?
    var relatedItemIDs: [UUID]?
    var message: String = ""
    var status: NudgeStatus = NudgeStatus.pending
    var scheduledFor: Date = Date.now
    var createdAt: Date = Date.now

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
