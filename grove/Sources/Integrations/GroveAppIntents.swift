#if !SHARE_EXTENSION
import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

// MARK: - App Entities

/// A sendable snapshot of a SwiftData board for App Intents and Spotlight.
///
/// App Intents must not retain SwiftData models across actor boundaries, so
/// queries and intents exchange these value types and resolve IDs inside a
/// fresh `ModelContext`.
struct GroveBoardEntity: IndexedEntity, URLRepresentableEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Grove Board",
        numericFormat: "\(placeholder: .int) Grove boards"
    )
    static let defaultQuery = GroveBoardEntityQuery()
    static var urlRepresentation: URLRepresentation {
        "grove://board/\(.id)"
    }

    let id: UUID
    let title: String
    let boardDescription: String?
    let itemCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(itemCount) items",
            image: .init(systemName: "rectangle.stack")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = boardDescription
        attributes.keywords = ["Grove", "board"]
        return attributes
    }
}

/// A sendable snapshot of a SwiftData item for App Intents and Spotlight.
struct GroveItemEntity: IndexedEntity, URLRepresentableEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Grove Item",
        numericFormat: "\(placeholder: .int) Grove items"
    )
    static let defaultQuery = GroveItemEntityQuery()
    static var urlRepresentation: URLRepresentation {
        "grove://item/\(.id)"
    }

    let id: UUID
    let title: String
    let kind: String
    let contentPreview: String?
    let sourceURL: URL?
    let boardTitles: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: boardTitles.isEmpty ? "\(kind)" : "\(boardTitles.joined(separator: ", "))",
            image: .init(systemName: systemImageName)
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = contentPreview
        attributes.url = sourceURL
        attributes.keywords = ["Grove", kind] + boardTitles
        return attributes
    }

    private var systemImageName: String {
        switch kind {
        case "Article": "doc.richtext"
        case "Codebase": "terminal"
        case "Video": "play.rectangle"
        default: "note.text"
        }
    }
}

// MARK: - Entity Queries

struct GroveBoardEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [GroveBoardEntity] {
        try await GroveIntentModelStore.boards(identifiers: Set(identifiers))
    }

    func suggestedEntities() async throws -> [GroveBoardEntity] {
        try await GroveIntentModelStore.boards()
    }

    func entities(matching string: String) async throws -> [GroveBoardEntity] {
        try await GroveIntentModelStore.boards(matching: string)
    }
}

struct GroveItemEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [GroveItemEntity] {
        try await GroveIntentModelStore.items(identifiers: Set(identifiers))
    }

    func suggestedEntities() async throws -> [GroveItemEntity] {
        try await GroveIntentModelStore.items(limit: 20)
    }

    func entities(matching string: String) async throws -> [GroveItemEntity] {
        try await GroveIntentModelStore.items(matching: string, limit: 50)
    }
}

// MARK: - Intents

struct CaptureInGroveIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture in Grove"
    static let description = IntentDescription(
        "Save a note or URL to Grove. Choosing a board files and approves the item immediately."
    )

    @Parameter(
        title: "Text or URL",
        description: "A note, thought, or web URL to save"
    )
    var input: String

    @Parameter(
        title: "Board",
        description: "An optional board to save the item to"
    )
    var board: GroveBoardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$input) in Grove") {
            \.$board
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<GroveItemEntity> & ProvidesDialog {
        let entity = try await GroveIntentModelStore.capture(input: input, boardID: board?.id)
        try await GroveSpotlightIndexer.index(item: entity)

        if let board {
            return .result(
                value: entity,
                dialog: "Saved \(entity.title) to \(board.title)."
            )
        }
        return .result(value: entity, dialog: "Added \(entity.title) to your inbox.")
    }
}

struct SaveItemToBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Grove Item to Board"
    static let description = IntentDescription(
        "File an existing Grove item on a board and mark it active."
    )

    @Parameter(title: "Item")
    var item: GroveItemEntity

    @Parameter(title: "Board")
    var board: GroveBoardEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$item) to \(\.$board)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<GroveItemEntity> & ProvidesDialog {
        let entity = try await GroveIntentModelStore.save(itemID: item.id, toBoardID: board.id)
        try await GroveSpotlightIndexer.index(item: entity)
        return .result(
            value: entity,
            dialog: "Saved \(entity.title) to \(board.title)."
        )
    }
}

struct GroveAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureInGroveIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Save to \(.applicationName)",
                "Add to \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "leaf"
        )

        AppShortcut(
            intent: SaveItemToBoardIntent(),
            phrases: [
                "File an item in \(.applicationName)",
                "Save a Grove item to a board in \(.applicationName)",
            ],
            shortTitle: "Save to Board",
            systemImageName: "rectangle.stack.badge.plus"
        )
    }
}

// MARK: - SwiftData Bridge

@MainActor
enum GroveIntentModelStore {
    private static var configuredContainer: ModelContainer?

    static func configure(with container: ModelContainer) {
        configuredContainer = container
    }

    static func boards(
        identifiers: Set<UUID>? = nil,
        matching searchText: String? = nil
    ) throws -> [GroveBoardEntity] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Board>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)])
        let boards = try context.fetch(descriptor)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return boards
            .filter { board in
                guard let identifiers else { return true }
                return identifiers.contains(board.id)
            }
            .filter { board in
                guard let normalizedSearch, !normalizedSearch.isEmpty else { return true }
                return board.title.localizedStandardContains(normalizedSearch)
                    || board.boardDescription?.localizedStandardContains(normalizedSearch) == true
            }
            .map(GroveBoardEntity.init)
    }

    static func items(
        identifiers: Set<UUID>? = nil,
        matching searchText: String? = nil,
        limit: Int? = nil
    ) throws -> [GroveItemEntity] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let items = try context.fetch(descriptor)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)

        let results = items
            .filter { item in
                guard item.status != .dismissed else { return false }
                guard let identifiers else { return true }
                return identifiers.contains(item.id)
            }
            .filter { item in
                guard let normalizedSearch, !normalizedSearch.isEmpty else { return true }
                return item.title.localizedStandardContains(normalizedSearch)
                    || item.content?.localizedStandardContains(normalizedSearch) == true
                    || item.boards.contains { $0.title.localizedStandardContains(normalizedSearch) }
            }
            .map(GroveItemEntity.init)

        if let limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    static func capture(input: String, boardID: UUID?) throws -> GroveItemEntity {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GroveIntentError.emptyCapture
        }

        let context = ModelContext(container)
        let board: Board?
        if let boardID {
            guard let resolvedBoard = try fetchBoard(id: boardID, in: context) else {
                throw GroveIntentError.boardNotFound
            }
            guard !resolvedBoard.isSmart else {
                throw GroveIntentError.smartBoardCannotAcceptItems
            }
            board = resolvedBoard
        } else {
            board = nil
        }

        // Reuse the app's capture pipeline so URL metadata, thumbnails, and
        // auto-tagging continue after the intent's durable save completes.
        let service = CaptureService(modelContext: context)
        let item = service.captureItem(input: trimmed, board: board)
        try context.save()
        return GroveItemEntity(item)
    }

    static func save(itemID: UUID, toBoardID boardID: UUID) throws -> GroveItemEntity {
        let context = ModelContext(container)
        guard let item = try fetchItem(id: itemID, in: context) else {
            throw GroveIntentError.itemNotFound
        }
        guard let board = try fetchBoard(id: boardID, in: context) else {
            throw GroveIntentError.boardNotFound
        }
        guard !board.isSmart else {
            throw GroveIntentError.smartBoardCannotAcceptItems
        }

        if !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
        }
        item.status = .active
        item.updatedAt = .now
        try context.save()
        return GroveItemEntity(item)
    }

    private static var container: ModelContainer {
        if let configuredContainer {
            return configuredContainer
        }
        let container = SharedModelContainer.makeForApp()
        configuredContainer = container
        return container
    }

    private static func fetchBoard(id: UUID, in context: ModelContext) throws -> Board? {
        var descriptor = FetchDescriptor<Board>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchItem(id: UUID, in context: ModelContext) throws -> Item? {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

}

// MARK: - Spotlight

@MainActor
enum GroveSpotlightIndexer {
    static func refreshAll(using container: ModelContainer? = nil) async {
        if let container {
            GroveIntentModelStore.configure(with: container)
        }

        do {
            async let boards = GroveIntentModelStore.boards()
            async let items = GroveIntentModelStore.items()
            try await replaceIndex(boards: boards, items: items)
        } catch {
            // Search indexing must never prevent the app from launching.
        }
    }

    static func index(item: GroveItemEntity) async throws {
        try await CSSearchableIndex.default().indexAppEntities([item])
    }

    private static func replaceIndex(
        boards: [GroveBoardEntity],
        items: [GroveItemEntity]
    ) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteAppEntities(ofType: GroveBoardEntity.self)
        try await index.deleteAppEntities(ofType: GroveItemEntity.self)
        try await index.indexAppEntities(boards)
        try await index.indexAppEntities(items)
    }
}

// MARK: - Mapping and Errors

private extension GroveBoardEntity {
    init(_ board: Board) {
        id = board.id
        title = board.title
        boardDescription = board.boardDescription
        itemCount = board.items.count
    }
}

private extension GroveItemEntity {
    init(_ item: Item) {
        id = item.id
        title = item.title
        kind = item.type.intentDisplayName
        contentPreview = item.content.map { String($0.prefix(500)) }
        sourceURL = item.sourceURL.flatMap(URL.init(string:))
        boardTitles = item.boards.map(\.title).sorted()
    }
}

private extension ItemType {
    var intentDisplayName: String {
        switch self {
        case .article: "Article"
        case .codebase: "Codebase"
        case .video: "Video"
        case .note: "Note"
        case .courseLecture: "Course lecture"
        }
    }
}

private enum GroveIntentError: LocalizedError {
    case emptyCapture
    case itemNotFound
    case boardNotFound
    case smartBoardCannotAcceptItems

    var errorDescription: String? {
        switch self {
        case .emptyCapture:
            "Enter a note or URL to capture."
        case .itemNotFound:
            "The Grove item no longer exists."
        case .boardNotFound:
            "The Grove board no longer exists."
        case .smartBoardCannotAcceptItems:
            "Smart boards collect items by rules and cannot accept manual assignments."
        }
    }
}
#endif
