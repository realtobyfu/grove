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

extension Legacy {
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
}

typealias Nudge = Legacy.Nudge

extension Nudge {
    /// The user-facing message. For dialectical check-ins, extracts the portion before `|||`.
    var displayMessage: String {
        var text = message
        if type == .dialecticalCheckIn, let range = text.range(of: "|||") {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        // Older resurface nudges persisted a "Connected to: <title>" suffix,
        // which could be a raw URL or markdown. Hide it on display.
        if let range = text.range(of: "Connected to:") {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
