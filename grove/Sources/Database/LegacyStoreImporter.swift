import Foundation
import SQLiteData
import SwiftData

/// Brings a SwiftData store into a new SQLite database, once.
///
/// The store is never opened where it lives, because opening a store through
/// SwiftData can migrate it in place. A copy is opened instead, the rows go into
/// a temporary database in one transaction, and that file only moves into place
/// after it has been checked against the copy. Anything short of that leaves no
/// database behind, so the next launch tries again from the untouched store.
enum LegacyStoreImporter {
    enum ImportError: Error, LocalizedError {
        case mismatch(table: String, expected: Int, actual: Int)
        case copyFailed(URL, underlying: any Error)

        var errorDescription: String? {
            switch self {
            case let .mismatch(table, expected, actual):
                "\(table) did not match the original library: expected \(expected) rows, wrote \(actual)."
            case let .copyFailed(url, underlying):
                "Could not copy \(url.lastPathComponent): \(underlying.localizedDescription)"
            }
        }
    }

    struct Report: Equatable, Sendable {
        /// Rows written, by table.
        var rowCounts: [String: Int]
        /// Rows dropped for repeating another row's ID, by table. Sync can leave
        /// such rows behind; the new primary keys can't hold them.
        var duplicatesDropped: [String: Int]
    }

    /// Imports the store at `source` and places the result at `destination`,
    /// which must not exist yet.
    @discardableResult
    static func run(source: URL, destination: URL) throws -> Report {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        removeLeftovers(in: directory)

        let workspace = directory.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let sourceCopy = try copyStore(at: source, into: workspace)
        let snapshot = try LegacySnapshot(storeAt: sourceCopy)

        let staged = workspace.appendingPathComponent(destination.lastPathComponent)
        try write(snapshot, to: staged)
        try verify(staged, against: snapshot)

        try fileManager.moveItem(at: staged, to: destination)
        return snapshot.report
    }

    /// A crash mid-import leaves a workspace behind. Only this importer writes
    /// `.import-` folders, and they only ever hold copies.
    private static func removeLeftovers(in directory: URL) {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix(".import-") {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Copies the store's files, keeping their names so the copy finds its own
    /// `.<name>_SUPPORT` folder. Returns the URL of the copied store.
    private static func copyStore(at source: URL, into workspace: URL) throws -> URL {
        let fileManager = FileManager.default
        let folder = workspace.appendingPathComponent("source", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let name = source.lastPathComponent
        let stem = source.deletingPathExtension().lastPathComponent
        for fileName in [name, "\(name)-wal", "\(name)-shm", ".\(stem)_SUPPORT"] {
            let file = source.deletingLastPathComponent().appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
            do {
                try fileManager.copyItem(at: file, to: folder.appendingPathComponent(fileName))
            } catch {
                throw ImportError.copyFailed(file, underlying: error)
            }
        }
        return folder.appendingPathComponent(name)
    }

    // MARK: - Writing

    /// Writes `snapshot` to a new file at `url` in a single transaction. The
    /// connection is closed on return, and DELETE journaling keeps it to one file.
    static func write(_ snapshot: LegacySnapshot, to url: URL) throws {
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false), configuration: AppDatabase.configuration())
        try AppDatabase.migrator.migrate(queue)
        try queue.write { db in
            for row in snapshot.boards { try Board.insert { row }.execute(db) }
            for row in snapshot.items { try Item.insert { row }.execute(db) }
            for row in snapshot.thumbnails { try ItemThumbnail.insert { row }.execute(db) }
            for row in snapshot.tags { try Tag.insert { row }.execute(db) }
            for row in snapshot.itemTags { try ItemTag.insert { row }.execute(db) }
            for row in snapshot.smartRuleTags { try BoardSmartRuleTag.insert { row }.execute(db) }
            for row in snapshot.connections { try Connection.insert { row }.execute(db) }
            for row in snapshot.annotations { try Annotation.insert { row }.execute(db) }
            for row in snapshot.conversations { try Conversation.insert { row }.execute(db) }
            for row in snapshot.reflections { try ReflectionBlock.insert { row }.execute(db) }
            for row in snapshot.messages { try ChatMessage.insert { row }.execute(db) }
            for row in snapshot.nudges { try Nudge.insert { row }.execute(db) }
            for row in snapshot.feedSources { try FeedSource.insert { row }.execute(db) }
            for row in snapshot.flashcards { try Flashcard.insert { row }.execute(db) }
            for row in snapshot.reviews { try FlashcardReview.insert { row }.execute(db) }
            for row in snapshot.preferences { try LearningPreferences.insert { row }.execute(db) }
            for row in snapshot.extraBoardLinks { try ExtraBoardLink.insert { row }.execute(db) }
        }
        try queue.close()
    }

    // MARK: - Verifying

    /// Throws unless the database at `url` holds every row and link of
    /// `snapshot`, and those rows account for every row the store counted. IDs
    /// are compared as well as counts, so one row standing in for another can't
    /// pass.
    static func verify(_ url: URL, against snapshot: LegacySnapshot) throws {
        var configuration = AppDatabase.configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false), configuration: configuration)
        defer { try? queue.close() }

        try queue.read { db in
            func expect<ID: Hashable>(_ table: String, _ written: [ID], _ expected: [ID]) throws {
                guard written.count == expected.count, Set(written) == Set(expected) else {
                    throw ImportError.mismatch(table: table, expected: expected.count, actual: written.count)
                }
                if let sourceCount = snapshot.sourceRowCounts[table] {
                    let accountedFor = written.count + (snapshot.duplicatesDropped[table] ?? 0)
                    guard accountedFor == sourceCount else {
                        throw ImportError.mismatch(table: table, expected: sourceCount, actual: accountedFor)
                    }
                }
            }
            try expect("boards", Board.select(\.id).fetchAll(db), snapshot.boards.map(\.id))
            try expect("items", Item.select(\.id).fetchAll(db), snapshot.items.map(\.id))
            try expect("itemThumbnails", ItemThumbnail.select(\.itemID).fetchAll(db), snapshot.thumbnails.map(\.itemID))
            try expect("tags", Tag.select(\.id).fetchAll(db), snapshot.tags.map(\.id))
            try expect("itemTags", ItemTag.select(\.id).fetchAll(db), snapshot.itemTags.map(\.id))
            try expect("boardSmartRuleTags", BoardSmartRuleTag.select(\.id).fetchAll(db), snapshot.smartRuleTags.map(\.id))
            try expect("connections", Connection.select(\.id).fetchAll(db), snapshot.connections.map(\.id))
            try expect("annotations", Annotation.select(\.id).fetchAll(db), snapshot.annotations.map(\.id))
            try expect("reflectionBlocks", ReflectionBlock.select(\.id).fetchAll(db), snapshot.reflections.map(\.id))
            try expect("conversations", Conversation.select(\.id).fetchAll(db), snapshot.conversations.map(\.id))
            try expect("chatMessages", ChatMessage.select(\.id).fetchAll(db), snapshot.messages.map(\.id))
            try expect("nudges", Nudge.select(\.id).fetchAll(db), snapshot.nudges.map(\.id))
            try expect("feedSources", FeedSource.select(\.id).fetchAll(db), snapshot.feedSources.map(\.id))
            try expect("flashcards", Flashcard.select(\.id).fetchAll(db), snapshot.flashcards.map(\.id))
            try expect("flashcardReviews", FlashcardReview.select(\.id).fetchAll(db), snapshot.reviews.map(\.id))
            try expect("learningPreferences", LearningPreferences.select(\.id).fetchAll(db), snapshot.preferences.map(\.id))
            try expect("extraBoardLinks", ExtraBoardLink.select(\.id).fetchAll(db), snapshot.extraBoardLinks.map(\.id))

            // Every board link the store held, wherever it landed.
            struct Link: Hashable { let itemID: UUID, boardID: UUID }
            let primary = try Item.where { $0.boardID.isNot(nil) }.fetchAll(db)
                .map { Link(itemID: $0.id, boardID: $0.boardID!) }
            let extra = try ExtraBoardLink.all.fetchAll(db).map { Link(itemID: $0.itemID, boardID: $0.boardID) }
            try expect(
                "board links",
                primary + extra,
                snapshot.boardLinks.map { Link(itemID: $0.itemID, boardID: $0.boardID) }
            )
        }
    }
}

/// Everything in a SwiftData store, as rows for the new tables.
struct LegacySnapshot {
    var boards: [Board] = []
    var items: [Item] = []
    var thumbnails: [ItemThumbnail] = []
    var tags: [Tag] = []
    var itemTags: [ItemTag] = []
    var smartRuleTags: [BoardSmartRuleTag] = []
    var connections: [Connection] = []
    var annotations: [Annotation] = []
    var reflections: [ReflectionBlock] = []
    var conversations: [Conversation] = []
    var messages: [ChatMessage] = []
    var nudges: [Nudge] = []
    var feedSources: [FeedSource] = []
    var flashcards: [Flashcard] = []
    var reviews: [FlashcardReview] = []
    var preferences: [LearningPreferences] = []
    var extraBoardLinks: [ExtraBoardLink] = []
    /// Every item-to-board link in the store. An item keeps its first as
    /// `boardID`, and the rest become `extraBoardLinks`.
    var boardLinks: [(itemID: UUID, boardID: UUID)] = []
    var duplicatesDropped: [String: Int] = [:]
    /// Rows the store reports having, by table, counted apart from the fetches
    /// that read them.
    var sourceRowCounts: [String: Int] = [:]

    init() {}

    /// Reads the store at `url`, which goes through `SharedModelContainer` and so
    /// handles every store era. Pass a copy: opening a store can migrate it.
    init(storeAt url: URL) throws {
        let configuration = ModelConfiguration(
            "Grove",
            schema: SharedModelContainer.schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try SharedModelContainer.openContainer(configuration)
        try self.init(ModelContext(container))
    }

    private init(_ context: ModelContext) throws {
        // Where IDs repeat, the most recently written row wins.
        func unique<T: PersistentModel>(
            _ table: String,
            _ type: T.Type,
            id: (T) -> UUID,
            newestFirst: (T, T) -> Bool
        ) throws -> [T] {
            sourceRowCounts[table] = try context.fetchCount(FetchDescriptor<T>())
            let rows = try context.fetch(FetchDescriptor<T>())
            var seen = Set<UUID>()
            let kept = rows.sorted(by: newestFirst).filter { seen.insert(id($0)).inserted }
            if kept.count != rows.count { duplicatesDropped[table] = rows.count - kept.count }
            return kept
        }

        let legacyBoards = try unique("boards", Legacy.Board.self, id: \.id) { $0.createdAt > $1.createdAt }
        let legacyItems = try unique("items", Legacy.Item.self, id: \.id) { $0.updatedAt > $1.updatedAt }
        let legacyTags = try unique("tags", Legacy.Tag.self, id: \.id) {
            ($0.trendCalculatedAt ?? .distantPast) > ($1.trendCalculatedAt ?? .distantPast)
        }

        boards = legacyBoards.map { board in
            Board(
                id: board.id,
                title: board.title,
                boardDescription: board.boardDescription,
                icon: board.icon,
                color: board.color,
                createdAt: board.createdAt,
                sortOrder: board.sortOrder,
                isSmart: board.isSmart,
                smartRuleLogic: board.smartRuleLogic,
                nudgeFrequencyHours: board.nudgeFrequencyHours,
                itemOrder: board.itemOrderData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
            )
        }

        var itemTagIDs = Set<UUID>()
        var extraLinkIDs = Set<UUID>()
        for item in legacyItems {
            // An item can sit on several boards here but only one in the new
            // schema: it keeps its first, and the others are held for later.
            let linked = item.boards.sorted(by: Self.boardOrder)
            var seenBoards = Set<UUID>()
            let distinct = linked.filter { seenBoards.insert($0.id).inserted }
            boardLinks += distinct.map { (item.id, $0.id) }
            for board in distinct.dropFirst() {
                let link = ExtraBoardLink(itemID: item.id, boardID: board.id)
                if extraLinkIDs.insert(link.id).inserted { extraBoardLinks.append(link) }
            }

            items.append(Item(
                id: item.id,
                title: item.title,
                type: item.type,
                status: item.status,
                sourceURL: item.sourceURL,
                content: item.content,
                engagementScore: item.engagementScore,
                metadata: item.metadata,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                readLaterUntil: item.readLaterUntil,
                lastResurfacedAt: item.lastResurfacedAt,
                resurfaceIntervalDays: item.resurfaceIntervalDays,
                resurfaceCount: item.resurfaceCount,
                lastEngagedAt: item.lastEngagedAt,
                isResurfacingPaused: item.isResurfacingPaused,
                boardID: distinct.first?.id
            ))
            if let thumbnail = item.thumbnail {
                thumbnails.append(ItemThumbnail(itemID: item.id, imageData: thumbnail))
            }
            for tag in item.tags {
                let row = ItemTag(itemID: item.id, tagID: tag.id)
                if itemTagIDs.insert(row.id).inserted { itemTags.append(row) }
            }
        }

        var smartRuleIDs = Set<UUID>()
        for board in legacyBoards {
            for tag in board.smartRuleTags {
                let row = BoardSmartRuleTag(boardID: board.id, tagID: tag.id)
                if smartRuleIDs.insert(row.id).inserted { smartRuleTags.append(row) }
            }
        }

        tags = legacyTags.map { tag in
            Tag(
                id: tag.id,
                name: tag.name,
                isAutoGenerated: tag.isAutoGenerated,
                confidence: tag.confidence,
                category: tag.category,
                parentTagID: tag.parentTag?.id,
                previousItemCount: tag.previousItemCount,
                trendCalculatedAt: tag.trendCalculatedAt
            )
        }

        connections = try unique("connections", Legacy.Connection.self, id: \.id) { $0.createdAt > $1.createdAt }
            .map { connection in
                Connection(
                    id: connection.id,
                    sourceItemID: connection.sourceItem?.id,
                    targetItemID: connection.targetItem?.id,
                    type: connection.type,
                    note: connection.note,
                    isAutoGenerated: connection.isAutoGenerated,
                    createdAt: connection.createdAt
                )
            }

        annotations = try unique("annotations", Legacy.Annotation.self, id: \.id) { $0.createdAt > $1.createdAt }
            .map { annotation in
                Annotation(
                    id: annotation.id,
                    itemID: annotation.item?.id,
                    content: annotation.content,
                    highlight: annotation.highlight,
                    position: annotation.position,
                    createdAt: annotation.createdAt
                )
            }

        reflections = try unique("reflectionBlocks", Legacy.ReflectionBlock.self, id: \.id) { $0.createdAt > $1.createdAt }
            .map { block in
                ReflectionBlock(
                    id: block.id,
                    itemID: block.item?.id,
                    blockTypeRaw: block.blockTypeRaw,
                    content: block.content,
                    highlight: block.highlight,
                    position: block.position,
                    videoTimestamp: block.videoTimestamp,
                    conversationID: block.conversation?.id,
                    createdAt: block.createdAt
                )
            }

        conversations = try unique("conversations", Legacy.Conversation.self, id: \.id) { $0.updatedAt > $1.updatedAt }
            .map { conversation in
                Conversation(
                    id: conversation.id,
                    title: conversation.title,
                    trigger: conversation.trigger,
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt,
                    isArchived: conversation.isArchived,
                    boardID: conversation.board?.id,
                    seedItemIDs: conversation.seedItemIDs
                )
            }

        messages = try unique("chatMessages", Legacy.ChatMessage.self, id: \.id) { $0.createdAt > $1.createdAt }
            .map { message in
                ChatMessage(
                    id: message.id,
                    conversationID: message.conversation?.id,
                    role: message.role,
                    content: message.content,
                    position: message.position,
                    createdAt: message.createdAt,
                    referencedItemIDs: message.referencedItemIDs,
                    toolCallName: message.toolCallName,
                    isHidden: message.isHidden
                )
            }

        nudges = try unique("nudges", Legacy.Nudge.self, id: \.id) { $0.createdAt > $1.createdAt }
            .map { nudge in
                Nudge(
                    id: nudge.id,
                    type: nudge.type,
                    targetItemID: nudge.targetItem?.id,
                    relatedItemIDs: nudge.relatedItemIDs,
                    message: nudge.message,
                    status: nudge.status,
                    scheduledFor: nudge.scheduledFor,
                    createdAt: nudge.createdAt
                )
            }

        feedSources = try unique("feedSources", Legacy.FeedSource.self, id: \.id) { $0.createdAt > $1.createdAt }
            .map { source in
                FeedSource(
                    id: source.id,
                    feedURL: source.feedURL,
                    domain: source.domain,
                    title: source.title,
                    lastFetchedAt: source.lastFetchedAt,
                    isEnabled: source.isEnabled,
                    isAutoDiscovered: source.isAutoDiscovered,
                    isUserSubscribed: source.isUserSubscribed,
                    errorCount: source.errorCount,
                    createdAt: source.createdAt
                )
            }

        flashcards = try unique("flashcards", Legacy.UserFlashcard.self, id: \.id) { $0.updatedAt > $1.updatedAt }
            .map { card in
                Flashcard(
                    id: card.id,
                    question: card.question,
                    answer: card.answer,
                    hints: card.hints,
                    sourceItemID: card.sourceItemID,
                    sourceReflectionID: card.sourceReflectionID,
                    sourceTitle: card.sourceTitle,
                    sourceQuote: card.sourceQuote,
                    sourceURL: card.sourceURL,
                    sourceLocator: card.sourceLocator,
                    boardIDs: card.boardIDs,
                    revision: card.revision,
                    revisionStartedAt: card.revisionStartedAt,
                    createdAt: card.createdAt,
                    updatedAt: card.updatedAt,
                    isSuspended: card.isSuspended,
                    dueAt: card.dueAt,
                    revisionFingerprint: card.revisionFingerprint,
                    deletedAt: card.deletedAt
                )
            }

        reviews = try unique("flashcardReviews", Legacy.UserFlashcardReview.self, id: \.id) { $0.reviewedAt > $1.reviewedAt }
            .map { review in
                FlashcardReview(
                    id: review.id,
                    cardID: review.cardID,
                    cardRevision: review.cardRevision,
                    cardFingerprint: review.cardFingerprint,
                    reviewedAt: review.reviewedAt,
                    ratingRaw: review.ratingRaw,
                    usedHint: review.usedHint,
                    readSource: review.readSource,
                    sessionID: review.sessionID
                )
            }

        // Two devices can each create the fixed-ID preferences row, so the
        // newest is the one a person last chose.
        preferences = try unique("learningPreferences", Legacy.UserLearningPreferences.self, id: \.id) { $0.updatedAt > $1.updatedAt }
            .map { preferences in
                LearningPreferences(
                    id: preferences.id,
                    focusBoardIDs: preferences.focusBoardIDs,
                    sessionMinutes: preferences.sessionMinutes,
                    updatedAt: preferences.updatedAt
                )
            }
    }

    /// The board an item keeps is the one highest on the sidebar. The remaining
    /// keys only make the choice repeatable, so that every device agrees.
    private static func boardOrder(_ lhs: Legacy.Board, _ rhs: Legacy.Board) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    var report: LegacyStoreImporter.Report {
        LegacyStoreImporter.Report(
            rowCounts: [
                "boards": boards.count,
                "items": items.count,
                "itemThumbnails": thumbnails.count,
                "tags": tags.count,
                "itemTags": itemTags.count,
                "boardSmartRuleTags": smartRuleTags.count,
                "connections": connections.count,
                "annotations": annotations.count,
                "reflectionBlocks": reflections.count,
                "conversations": conversations.count,
                "chatMessages": messages.count,
                "nudges": nudges.count,
                "feedSources": feedSources.count,
                "flashcards": flashcards.count,
                "flashcardReviews": reviews.count,
                "learningPreferences": preferences.count,
                "extraBoardLinks": extraBoardLinks.count,
            ],
            duplicatesDropped: duplicatesDropped
        )
    }
}
