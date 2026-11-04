import Foundation
import SQLiteData

enum ConversationTrigger: String, Codable, QueryBindable {
    case userInitiated
    case contradictionDetected
    case knowledgeGap
    case staleItems
    case periodicReflection
}

/// Registered as a private table, so a shared board never carries its chats.
@Table("conversations")
struct Conversation: Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String = ""
    var trigger: ConversationTrigger = .userInitiated
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var isArchived: Bool = false
    var boardID: Board.ID?
    @Column(as: [UUID].JSONRepresentation.self)
    var seedItemIDs: [UUID] = []
}

extension Conversation {
    init(
        title: String = "New Conversation",
        trigger: ConversationTrigger = .userInitiated,
        boardID: Board.ID? = nil,
        seedItemIDs: [UUID] = []
    ) {
        self.init(id: UUID(), title: title, trigger: trigger, boardID: boardID, seedItemIDs: seedItemIDs)
    }
}
