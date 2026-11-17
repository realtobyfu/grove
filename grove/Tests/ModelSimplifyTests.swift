import Foundation
import SwiftData
import Testing
@testable import grove

/// Retired connection types, item types and conversation triggers stop being
/// offered or produced, but synced stores still hold their raw values, so each
/// must keep decoding and rendering.
@MainActor
struct ModelSimplifyTests {

    // MARK: - Connection types

    @Test func pickersOfferExactlyThreeConnectionTypes() {
        #expect(ConnectionType.userSelectableCases == [.related, .contradicts, .buildsOn])
    }

    @Test(arguments: [
        ("sameTopic", ConnectionType.sameTopic, "Same Topic"),
        ("inspiredBy", ConnectionType.inspiredBy, "Inspired By"),
    ])
    func retiredConnectionTypesDecodeAndKeepTheirLabel(
        rawValue: String, expected: ConnectionType, label: String
    ) throws {
        let decoded = try decode(ConnectionType.self, rawValue)

        #expect(decoded == expected)
        #expect(decoded.displayLabel(isOutgoing: true) == label)
        #expect(decoded.displayLabel(isOutgoing: false) == label)
    }

    @Test func linkedFromKeepsItsDirectionalLabelsAndStaysAutomatic() throws {
        let decoded = try decode(ConnectionType.self, "linkedFrom")

        #expect(decoded.displayLabel(isOutgoing: true) == "Links To")
        #expect(decoded.displayLabel(isOutgoing: false) == "Linked From")
        #expect(!ConnectionType.userSelectableCases.contains(.linkedFrom))
    }

    @Test func retiredConnectionSurvivesAStoreRoundTrip() throws {
        let context = try makeContext()
        let source = Item(title: "Source", type: .note)
        let target = Item(title: "Target", type: .note)
        context.insert(source)
        context.insert(target)
        context.insert(Connection(sourceItem: source, targetItem: target, type: .sameTopic))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Connection>()).first)

        #expect(stored.type == .sameTopic)
        #expect(stored.type.displayLabel == "Same Topic")
    }

    // MARK: - Item types

    @Test(arguments: [
        "https://github.com/apple/swift",
        "https://www.github.com/apple/swift/issues/1",
    ])
    func gitHubURLCapturesAsArticle(urlString: String) {
        let item = Item(title: urlString, type: .note)

        CaptureService.applyURLClassification(item: item, urlString: urlString)

        #expect(item.type == .article)
        #expect(item.sourceURL == urlString)
    }

    @Test(arguments: [
        ("codebase", ItemType.codebase, "terminal", "codebase"),
        ("courseLecture", ItemType.courseLecture, "graduationcap", "course lecture"),
    ])
    func retiredItemTypesDecodeAndKeepTheirDisplay(
        rawValue: String, expected: ItemType, icon: String, llmLabel: String
    ) throws {
        let decoded = try decode(ItemType.self, rawValue)

        #expect(decoded == expected)
        #expect(decoded.iconName == icon)
        #expect(decoded.llmLabel == llmLabel)
    }

    @Test func existingCodebaseItemStillOpensInTheWebReader() throws {
        let context = try makeContext()
        let item = Item(title: "swift", type: .codebase)
        item.sourceURL = "https://github.com/apple/swift"
        context.insert(item)

        let viewModel = ItemReaderViewModel(item: item, modelContext: context)

        #expect(viewModel.articleURL?.absoluteString == "https://github.com/apple/swift")
    }

    // MARK: - Conversation triggers

    @Test(arguments: [
        ("userInitiated", ConversationTrigger.userInitiated),
        ("contradictionDetected", ConversationTrigger.contradictionDetected),
        ("knowledgeGap", ConversationTrigger.knowledgeGap),
        ("staleItems", ConversationTrigger.staleItems),
        ("periodicReflection", ConversationTrigger.periodicReflection),
    ])
    func everyConversationTriggerStillDecodes(rawValue: String, expected: ConversationTrigger) throws {
        #expect(try decode(ConversationTrigger.self, rawValue) == expected)
    }

    @Test(arguments: [
        ConversationTrigger.contradictionDetected, .knowledgeGap, .staleItems, .periodicReflection,
    ])
    func untitledConversationReadsTheSameWhateverItsTrigger(trigger: ConversationTrigger) {
        let current = Conversation(trigger: .userInitiated)
        let retired = Conversation(trigger: trigger)
        retired.createdAt = current.createdAt

        #expect(retired.displayTitle == current.displayTitle)
        #expect(retired.displayTitle == "New conversation")
    }

    @Test func titledConversationKeepsItsTitleWhateverItsTrigger() {
        let conversation = Conversation(title: "Moss and memory", trigger: .periodicReflection)

        #expect(conversation.displayTitle == "Moss and memory")
    }

    // MARK: - Board colour

    @Test func editingABoardLeavesItsStoredColorAlone() throws {
        let context = try makeContext()
        let board = Board(title: "Moss", icon: "leaf", color: "#336644")
        context.insert(board)

        BoardViewModel(modelContext: context).updateBoard(board, title: "Lichen", icon: "star")

        #expect(board.title == "Lichen")
        #expect(board.icon == "star")
        #expect(board.color == "#336644")
    }

    @Test func recreatingABoardByNameLeavesItsStoredColorAlone() throws {
        let context = try makeContext()
        let board = Board(title: "Moss", icon: "leaf", color: "#336644")
        context.insert(board)
        try context.save()

        BoardViewModel(modelContext: context).createBoard(title: "Moss", icon: "star")

        #expect(try context.fetch(FetchDescriptor<Board>()).count == 1)
        #expect(board.icon == "star")
        #expect(board.color == "#336644")
    }

    @Test func newBoardHasNoColor() throws {
        let context = try makeContext()

        BoardViewModel(modelContext: context).createBoard(title: "Moss", icon: "leaf")

        let board = try #require(try context.fetch(FetchDescriptor<Board>()).first)
        #expect(board.color == nil)
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ rawValue: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data("\"\(rawValue)\"".utf8))
    }

    private func makeContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "ModelSimplifyTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }
}
