import Foundation
import SQLiteData

enum ChatRole: String, Codable, QueryBindable {
    case system
    case assistant
    case user
    case tool
}

@Table("chatMessages")
struct ChatMessage: Hashable, Identifiable, Sendable {
    let id: UUID
    var conversationID: Conversation.ID?
    var role: ChatRole = .user
    var content: String = ""
    var position: Int = 0
    var createdAt: Date = .now
    @Column(as: [UUID].JSONRepresentation.self)
    var referencedItemIDs: [UUID] = []
    var toolCallName: String?
    var isHidden: Bool = false
}

extension ChatMessage {
    init(
        role: ChatRole,
        content: String,
        position: Int,
        conversationID: Conversation.ID? = nil,
        isHidden: Bool = false,
        toolCallName: String? = nil,
        referencedItemIDs: [UUID] = []
    ) {
        self.init(
            id: UUID(),
            conversationID: conversationID,
            role: role,
            content: content,
            position: position,
            referencedItemIDs: referencedItemIDs,
            toolCallName: toolCallName,
            isHidden: isHidden
        )
    }
}

