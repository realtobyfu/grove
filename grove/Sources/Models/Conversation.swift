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

    /// Longest first-message title before it is cut with an ellipsis.
    static let derivedTitleLimit = 48

    /// The stored title once someone has named it; until then the board's
    /// discussion, else the opening line the user wrote, else a plain label.
    var displayTitle: String {
        guard title == "New Conversation" else { return title }
        if let boardName = board?.title { return "\(boardName) Discussion" }
        let firstUserText = sortedMessages
            .first { $0.role == .user && !$0.isHidden }?
            .content
        guard let derived = firstUserText.flatMap(Self.oneLineTitle(from:)) else {
            return "New conversation"
        }
        return derived
    }

    /// First non-empty line, whitespace collapsed, cut at a word boundary
    /// near `derivedTitleLimit` with an ellipsis. Nil when nothing is left.
    static func oneLineTitle(from text: String) -> String? {
        guard let line = text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map({ $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") })
            .first(where: { !$0.isEmpty })
        else { return nil }

        guard line.count > derivedTitleLimit else { return line }
        let cut = line.prefix(derivedTitleLimit)
        // Prefer ending on a whole word, unless that throws away most of it.
        if let space = cut.lastIndex(of: " "),
           cut.distance(from: cut.startIndex, to: space) >= derivedTitleLimit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
