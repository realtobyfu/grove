import Foundation
import SwiftData

/// Raw values are persisted in `Nudge.type`, so every case stays even after
/// its generator is retired. Only `staleInbox` is still produced.
enum NudgeType: String, Codable {
    // Active engine category.
    case staleInbox

    // Retired categories, kept so persisted records still decode.
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
