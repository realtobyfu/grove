import Foundation
import SQLiteData

// Tables hold rows, and rows don't know what they're linked to. These read
// models are what the app works with when it needs the links too: an item with
// its board and tags, a board with its items. They're plain values, loaded in
// bulk and replaced whole when the database changes.
//
// `@dynamicMemberLookup` makes each read like the row it wraps, so `item.title`
// and `item.tags` both work on an `ItemGraph`. Lookup is read-only on purpose:
// a value can't write itself back, so changes go through the database. See
// `Writes.swift`.

/// An item and what hangs off it.
@dynamicMemberLookup
struct ItemGraph: Hashable, Identifiable, Sendable {
    var item: Item
    var board: Board?
    /// By name.
    var tags: [Tag] = []
    /// By position.
    var reflections: [ReflectionBlock] = []
    var outgoingConnections: [ConnectionEdge] = []
    var incomingConnections: [ConnectionEdge] = []

    var id: Item.ID { item.id }

    subscript<Value>(dynamicMember keyPath: KeyPath<Item, Value>) -> Value {
        item[keyPath: keyPath]
    }

    // Identity is enough to hash on, and much cheaper than the whole graph.
    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
    }
}

/// A connection with both of its items resolved.
@dynamicMemberLookup
struct ConnectionEdge: Hashable, Identifiable, Sendable {
    var connection: Connection
    var sourceItem: Item?
    var targetItem: Item?

    var id: Connection.ID { connection.id }

    subscript<Value>(dynamicMember keyPath: KeyPath<Connection, Value>) -> Value {
        connection[keyPath: keyPath]
    }
}

/// A board and its items.
@dynamicMemberLookup
struct BoardGraph: Hashable, Identifiable, Sendable {
    var board: Board
    var items: [ItemGraph] = []
    var smartRuleTags: [Tag] = []

    var id: Board.ID { board.id }

    subscript<Value>(dynamicMember keyPath: KeyPath<Board, Value>) -> Value {
        board[keyPath: keyPath]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(board.id)
    }
}

/// A tag and what uses it.
@dynamicMemberLookup
struct TagGraph: Hashable, Identifiable, Sendable {
    var tag: Tag
    var items: [ItemGraph] = []
    var parentTag: Tag?
    var childTags: [Tag] = []
    var smartRuleBoards: [Board] = []

    var id: Tag.ID { tag.id }

    subscript<Value>(dynamicMember keyPath: KeyPath<Tag, Value>) -> Value {
        tag[keyPath: keyPath]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag.id)
    }
}

/// A conversation and its messages. Separate from `Library` because chats are
/// only read on the chat screens.
@dynamicMemberLookup
struct ConversationGraph: Hashable, Identifiable, Sendable {
    var conversation: Conversation
    var board: Board?
    var messages: [ChatMessage] = []
    var createdReflections: [ReflectionBlock] = []

    var id: Conversation.ID { conversation.id }

    subscript<Value>(dynamicMember keyPath: KeyPath<Conversation, Value>) -> Value {
        conversation[keyPath: keyPath]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(conversation.id)
    }
}

// MARK: - Library

/// Every item, board and tag, with their links. Reading it costs one pass over
/// each table, however many items there are.
///
/// In a view, `@Fetch(Library.Request()) private var library = Library()` keeps
/// this current. Equal requests share one observation, so any number of views
/// can do so for the cost of one. In a service, read it inside a transaction with
/// `try Library.fetch(db)`.
struct Library: Equatable, Sendable {
    var items: [ItemGraph] = []
    /// In sidebar order.
    var boards: [BoardGraph] = []
    var tags: [TagGraph] = []

    private var itemsByID: [Item.ID: Int] = [:]
    private var boardsByID: [Board.ID: Int] = [:]
    private var tagsByID: [Tag.ID: Int] = [:]

    init() {}

    func item(_ id: Item.ID?) -> ItemGraph? {
        id.flatMap { itemsByID[$0] }.map { items[$0] }
    }

    func board(_ id: Board.ID?) -> BoardGraph? {
        id.flatMap { boardsByID[$0] }.map { boards[$0] }
    }

    func tag(_ id: Tag.ID?) -> TagGraph? {
        id.flatMap { tagsByID[$0] }.map { tags[$0] }
    }

    struct Request: FetchKeyRequest {
        func fetch(_ db: Database) throws -> Library {
            try Library.fetch(db)
        }
    }

    static func fetch(_ db: Database) throws -> Library {
        let items = try Item.all.fetchAll(db)
        let boards = try Board.order(by: \.sortOrder).fetchAll(db)
        let tags = try Tag.all.fetchAll(db)
        let itemTags = try ItemTag.all.fetchAll(db)
        let smartRuleTags = try BoardSmartRuleTag.all.fetchAll(db)
        let connections = try Connection.all.fetchAll(db)
        let reflections = try ReflectionBlock.order(by: \.position).fetchAll(db)

        let itemRows = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let boardRows = Dictionary(boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tagRows = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var tagsByItem: [Item.ID: [Tag]] = [:]
        var itemIDsByTag: [Tag.ID: [Item.ID]] = [:]
        for link in itemTags {
            if let tag = tagRows[link.tagID] { tagsByItem[link.itemID, default: []].append(tag) }
            itemIDsByTag[link.tagID, default: []].append(link.itemID)
        }

        var outgoing: [Item.ID: [ConnectionEdge]] = [:]
        var incoming: [Item.ID: [ConnectionEdge]] = [:]
        for connection in connections {
            let edge = ConnectionEdge(
                connection: connection,
                sourceItem: connection.sourceItemID.flatMap { itemRows[$0] },
                targetItem: connection.targetItemID.flatMap { itemRows[$0] }
            )
            if let sourceID = connection.sourceItemID { outgoing[sourceID, default: []].append(edge) }
            if let targetID = connection.targetItemID { incoming[targetID, default: []].append(edge) }
        }

        let reflectionsByItem = Dictionary(grouping: reflections.filter { $0.itemID != nil }) { $0.itemID! }

        var library = Library()
        library.items = items.map { item in
            ItemGraph(
                item: item,
                board: item.boardID.flatMap { boardRows[$0] },
                tags: (tagsByItem[item.id] ?? []).sorted { $0.name < $1.name },
                reflections: reflectionsByItem[item.id] ?? [],
                outgoingConnections: outgoing[item.id] ?? [],
                incomingConnections: incoming[item.id] ?? []
            )
        }
        library.itemsByID = Dictionary(
            library.items.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        let itemsByBoard = Dictionary(grouping: library.items.filter { $0.boardID != nil }) { $0.boardID! }
        var ruleTagsByBoard: [Board.ID: [Tag]] = [:]
        var ruleBoardsByTag: [Tag.ID: [Board]] = [:]
        for rule in smartRuleTags {
            if let tag = tagRows[rule.tagID] { ruleTagsByBoard[rule.boardID, default: []].append(tag) }
            if let board = boardRows[rule.boardID] { ruleBoardsByTag[rule.tagID, default: []].append(board) }
        }
        library.boards = boards.map { board in
            BoardGraph(
                board: board,
                items: itemsByBoard[board.id] ?? [],
                smartRuleTags: ruleTagsByBoard[board.id] ?? []
            )
        }
        library.boardsByID = Dictionary(
            library.boards.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        let childrenByParent = Dictionary(grouping: tags.filter { $0.parentTagID != nil }) { $0.parentTagID! }
        library.tags = tags.map { tag in
            TagGraph(
                tag: tag,
                items: (itemIDsByTag[tag.id] ?? []).compactMap { library.item($0) },
                parentTag: tag.parentTagID.flatMap { tagRows[$0] },
                childTags: childrenByParent[tag.id] ?? [],
                smartRuleBoards: ruleBoardsByTag[tag.id] ?? []
            )
        }
        library.tagsByID = Dictionary(
            library.tags.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return library
    }
}

// MARK: - One at a time

extension ItemGraph {
    /// Keeps one item current in a view:
    /// `@Fetch(ItemGraph.Request(id: id)) private var item: ItemGraph?`
    struct Request: FetchKeyRequest {
        let id: Item.ID

        func fetch(_ db: Database) throws -> ItemGraph? {
            try ItemGraph.fetch(id, in: db)
        }
    }

    static func fetch(_ id: Item.ID, in db: Database) throws -> ItemGraph? {
        guard let item = try Item.find(id).fetchOne(db) else { return nil }
        return try ItemGraph(item, in: db)
    }

    /// Reads the links of `item`.
    init(_ item: Item, in db: Database) throws {
        let tagIDs = try ItemTag.where { $0.itemID.eq(item.id) }.select(\.tagID).fetchAll(db)
        let outgoing = try Connection.where { $0.sourceItemID.eq(item.id) }.fetchAll(db)
        let incoming = try Connection.where { $0.targetItemID.eq(item.id) }.fetchAll(db)

        let endIDs = Set((outgoing + incoming).flatMap { [$0.sourceItemID, $0.targetItemID] }.compactMap(\.self))
        let ends = try Item.where { $0.id.in(Array(endIDs)) }.fetchAll(db)
        let endsByID = Dictionary(ends.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func edge(_ connection: Connection) -> ConnectionEdge {
            ConnectionEdge(
                connection: connection,
                sourceItem: connection.sourceItemID.flatMap { endsByID[$0] },
                targetItem: connection.targetItemID.flatMap { endsByID[$0] }
            )
        }

        self.init(
            item: item,
            board: try item.boardID.flatMap { try Board.find($0).fetchOne(db) },
            tags: try Tag.where { $0.id.in(tagIDs) }.fetchAll(db).sorted { $0.name < $1.name },
            reflections: try ReflectionBlock.where { $0.itemID.eq(item.id) }.order(by: \.position).fetchAll(db),
            outgoingConnections: outgoing.map(edge),
            incomingConnections: incoming.map(edge)
        )
    }
}

extension ConversationGraph {
    /// Every conversation with its messages, most recently updated first.
    struct All: FetchKeyRequest {
        func fetch(_ db: Database) throws -> [ConversationGraph] {
            try ConversationGraph.fetchAll(db)
        }
    }

    /// Keeps one conversation current in a view.
    struct Request: FetchKeyRequest {
        let id: Conversation.ID

        func fetch(_ db: Database) throws -> ConversationGraph? {
            try ConversationGraph.fetch(id, in: db)
        }
    }

    static func fetchAll(_ db: Database) throws -> [ConversationGraph] {
        let conversations = try Conversation.order { $0.updatedAt.desc() }.fetchAll(db)
        let boards = try Board.all.fetchAll(db)
        let messages = try ChatMessage.all.fetchAll(db)
        let reflections = try ReflectionBlock.where { $0.conversationID.isNot(nil) }.fetchAll(db)

        let boardsByID = Dictionary(boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let messagesByConversation = Dictionary(grouping: messages.filter { $0.conversationID != nil }) { $0.conversationID! }
        let reflectionsByConversation = Dictionary(grouping: reflections) { $0.conversationID! }
        return conversations.map { conversation in
            ConversationGraph(
                conversation: conversation,
                board: conversation.boardID.flatMap { boardsByID[$0] },
                messages: messagesByConversation[conversation.id] ?? [],
                createdReflections: reflectionsByConversation[conversation.id] ?? []
            )
        }
    }

    static func fetch(_ id: Conversation.ID, in db: Database) throws -> ConversationGraph? {
        guard let conversation = try Conversation.find(id).fetchOne(db) else { return nil }
        return ConversationGraph(
            conversation: conversation,
            board: try conversation.boardID.flatMap { try Board.find($0).fetchOne(db) },
            messages: try ChatMessage.where { $0.conversationID.eq(id) }.fetchAll(db),
            createdReflections: try ReflectionBlock.where { $0.conversationID.eq(id) }.fetchAll(db)
        )
    }
}

// MARK: - Domain Logic That Needs Links

extension ItemGraph {
    /// Breakdown of engagement-depth components. UI no longer surfaces this;
    /// it survives as an internal ranking signal (e.g. chat context selection).
    private var computedScoreBreakdown: [(label: String, points: Int)] {
        var breakdown: [(label: String, points: Int)] = []

        if self.status != .inbox && self.status != .queued {
            breakdown.append(("Opened", 5))
        }

        let manualTags = tags.filter { !$0.isAutoGenerated }
        if !manualTags.isEmpty {
            breakdown.append(("Tagged", 5))
        }

        if reflections.count > 0 {
            breakdown.append(("Reflections ×\(reflections.count)", reflections.count * 25))
        }

        let connectionCount = outgoingConnections.count + incomingConnections.count
        if connectionCount > 0 {
            breakdown.append(("Connections ×\(connectionCount)", connectionCount * 15))
        }

        if let lastEngaged = self.lastEngagedAt {
            let daysSinceCreation = Calendar.current.dateComponents([.day], from: self.createdAt, to: lastEngaged).day ?? 0
            if daysSinceCreation >= 7 {
                breakdown.append(("Revisited", 10))
            }
        }

        return breakdown
    }

    /// Computed engagement score based on meaningful activities.
    var depthScore: Int {
        computedScoreBreakdown.reduce(0) { $0 + $1.points }
    }

    /// Whether this item is eligible for the resurfacing queue.
    /// Requires at least one reflection or connection.
    var isResurfacingEligible: Bool {
        !reflections.isEmpty || !outgoingConnections.isEmpty || !incomingConnections.isEmpty
    }

    /// Next resurfacing date based on lastResurfacedAt + interval, or lastEngagedAt + interval.
    var nextResurfaceDate: Date? {
        guard isResurfacingEligible, !self.isResurfacingPaused, self.status == .active else { return nil }
        let referenceDate = self.lastResurfacedAt ?? self.lastEngagedAt ?? self.createdAt
        return Calendar.current.date(byAdding: .day, value: self.resurfaceIntervalDays, to: referenceDate)
    }

    /// Whether this item is overdue for resurfacing.
    var isResurfacingOverdue: Bool {
        guard let nextDate = nextResurfaceDate else { return false }
        return nextDate <= .now
    }
}

extension BoardGraph {
    /// The manual order, keeping only items still on the board. An order that
    /// was never set is the board's own order.
    func manualOrder() -> [UUID] {
        guard !self.itemOrder.isEmpty else { return items.map(\.id) }
        let validIDs = Set(items.map(\.id))
        return self.itemOrder.filter { validIDs.contains($0) }
    }
}

extension TagGraph {
    /// Computed trend based on current vs previous item count
    var trend: TagTrend {
        let current = items.count
        let previous = self.previousItemCount
        if current > previous + 1 { return .increasing }
        if current < previous - 1 { return .decreasing }
        return .stable
    }
}

extension ConversationGraph {
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
        guard self.title == "New Conversation" else { return self.title }
        if let boardName = board?.title { return "\(boardName) Discussion" }
        switch self.trigger {
        case .contradictionDetected: return "Exploring a Contradiction"
        case .knowledgeGap:          return "Exploring a Knowledge Gap"
        case .staleItems:            return "Revisiting Old Items"
        case .periodicReflection:    return "Periodic Reflection"
        case .userInitiated:         break
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return "Conversation – \(f.string(from: self.createdAt))"
    }
}
