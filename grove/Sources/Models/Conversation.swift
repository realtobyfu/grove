import Foundation
import SwiftData

/// Raw values are persisted in `Conversation.trigger`, so every case stays.
/// Only `userInitiated` is still produced; the rest exist so old conversations
/// decode, and nothing branches on them.
enum ConversationTrigger: String, Codable {
    case userInitiated
    case contradictionDetected
    case knowledgeGap
    case staleItems
    case periodicReflection
}

@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = ""
    var trigger: ConversationTrigger = ConversationTrigger.userInitiated
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isArchived: Bool = false
    var board: Board?
    // See the note in `Board` — CloudKit requires optional relationships with
    // inverses; the computed accessors keep call sites on plain `[T]`.

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messagesStorage: [ChatMessage]? = []
    @Relationship(inverse: \ReflectionBlock.conversation)
    var createdReflectionsStorage: [ReflectionBlock]? = []

    var messages: [ChatMessage] {
        get { messagesStorage ?? [] }
        set { messagesStorage = newValue }
    }

    var createdReflections: [ReflectionBlock] {
        get { createdReflectionsStorage ?? [] }
        set { createdReflectionsStorage = newValue }
    }
    var seedItemIDs: [UUID] = []

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
        self.messagesStorage = []
        self.createdReflectionsStorage = []
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
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return "Conversation – \(f.string(from: createdAt))"
    }
}
