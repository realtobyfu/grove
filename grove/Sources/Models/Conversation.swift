import Foundation
import SwiftData

enum ConversationTrigger: String, Codable {
    case userInitiated
    case contradictionDetected
    case knowledgeGap
    case staleItems
    case periodicReflection
}

@Model
final class Conversation {
    var id: UUID
    var title: String
    var trigger: ConversationTrigger
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var board: Board?
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation) var messages: [ChatMessage]
    @Relationship(inverse: \ReflectionBlock.conversation) var createdReflections: [ReflectionBlock]
    var seedItemIDs: [UUID]

    init(
        title: String = "New Conversation",
        trigger: ConversationTrigger = .userInitiated,
        board: Board? = nil,
        seedItemIDs: [UUID] = []
    ) {
        self.id = UUID()
        self.title = title
        self.trigger = trigger
        self.createdAt = .now
        self.updatedAt = .now
        self.isArchived = false
        self.board = board
        self.messages = []
        self.createdReflections = []
        self.seedItemIDs = seedItemIDs
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.position < $1.position }
    }

    var visibleMessages: [ChatMessage] {
        sortedMessages.filter { !$0.isHidden }
    }

    /// Only conversations with a user-authored turn should appear in chat history.
    var hasUserMessages: Bool {
        messages.contains { $0.role == .user && !$0.isHidden }
    }

    var isSavedToHistory: Bool {
        hasUserMessages
    }

    var lastMessage: ChatMessage? {
        sortedMessages.last
    }

    var nextPosition: Int {
        (messages.map(\.position).max() ?? -1) + 1
    }

    var displayTitle: String {
        guard title == "New Conversation" else { return title }
        if let boardName = board?.title { return "\(boardName) Discussion" }
        switch trigger {
        case .contradictionDetected: return "Exploring a Contradiction"
        case .knowledgeGap:          return "Exploring a Knowledge Gap"
        case .staleItems:            return "Revisiting Old Items"
        case .periodicReflection:    return "Periodic Reflection"
        case .userInitiated:         break
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return "Conversation – \(f.string(from: createdAt))"
    }
}
