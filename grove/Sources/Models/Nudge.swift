import Foundation
import SQLiteData

enum NudgeType: String, Codable, QueryBindable {
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

enum NudgeStatus: String, Codable, QueryBindable {
    case pending
    case shown
    case actedOn
    case dismissed
}

@Table("nudges")
struct Nudge: Hashable, Identifiable, Sendable {
    let id: UUID
    var type: NudgeType = .resurface
    var targetItemID: Item.ID?
    @Column(as: [UUID]?.JSONRepresentation.self)
    var relatedItemIDs: [UUID]?
    var message: String = ""
    var status: NudgeStatus = .pending
    var scheduledFor: Date = .now
    var createdAt: Date = .now
}

extension Nudge {
    init(type: NudgeType, message: String, scheduledFor: Date = .now, targetItemID: Item.ID? = nil) {
        self.init(id: UUID(), type: type, targetItemID: targetItemID, message: message, scheduledFor: scheduledFor)
    }
}


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
