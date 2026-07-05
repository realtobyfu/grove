import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case system
    case assistant
    case user
    case tool
}

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var conversation: Conversation?
    var role: ChatRole = ChatRole.user
    var content: String = ""
    var position: Int = 0
    var createdAt: Date = Date.now
    var referencedItemIDs: [UUID] = []
    var toolCallName: String?
    var isHidden: Bool = false

    init(
        role: ChatRole,
        content: String,
        position: Int,
        isHidden: Bool = false,
        toolCallName: String? = nil,
        referencedItemIDs: [UUID] = []
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.position = position
        self.createdAt = .now
        self.referencedItemIDs = referencedItemIDs
        self.toolCallName = toolCallName
        self.isHidden = isHidden
    }
}
