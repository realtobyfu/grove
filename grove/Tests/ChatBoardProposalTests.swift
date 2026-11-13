import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import grove

/// Scripted provider that drives one native tool-calling turn.
private actor ScriptedProvider: LLMProvider {
    private var responses: [LLMChatResponse]
    private(set) var requests: [[ChatTurn]] = []
    private(set) var lastError: LLMError?

    init(responses: [LLMChatResponse]) {
        self.responses = responses
    }

    var supportsNativeTools: Bool { true }

    func complete(system: String, user: String) async -> LLMCompletionResult? { nil }

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? { nil }

    func completeChat(messages: [ChatTurn], tools: [LLMToolSpec], service: String) async -> LLMChatResponse? {
        requests.append(messages)
        guard !responses.isEmpty else { return nil }
        return responses.removeFirst()
    }
}

@MainActor
struct ChatBoardProposalTests {
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "ChatBoardProposalTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func insertItem(_ title: String, in context: ModelContext) -> Item {
        let item = Item(title: title, type: .note)
        item.status = .active
        context.insert(item)
        return item
    }

    /// A provider whose model calls `create_board` once, then replies.
    private func proposingProvider(boardName: String, itemTitles: String) -> ScriptedProvider {
        let arguments = try! JSONSerialization.data(
            withJSONObject: ["board_name": boardName, "item_titles": itemTitles]
        )
        let call = LLMToolCall(
            id: "call_1",
            name: "create_board",
            argumentsJSON: String(decoding: arguments, as: UTF8.self)
        )
        return ScriptedProvider(responses: [
            LLMChatResponse(content: nil, toolCalls: [call], inputTokens: 1, outputTokens: 1),
            LLMChatResponse(content: "It is waiting for you below.", toolCalls: [], inputTokens: 1, outputTokens: 1),
        ])
    }

    /// Runs a turn in which the model proposes a board.
    private func propose(
        boardName: String,
        itemTitles: String,
        provider: ScriptedProvider? = nil,
        context: ModelContext
    ) async -> (service: DialecticsService, conversation: Conversation) {
        let provider = provider ?? proposingProvider(boardName: boardName, itemTitles: itemTitles)
        let service = DialecticsService(provider: provider)
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil,
            context: context
        )
        _ = await service.sendMessage(
            userText: "Group these for me.",
            conversation: conversation,
            context: context
        )
        return (service, conversation)
    }

    // MARK: - Tool

    @Test func toolWritesNothingAndSaysTheBoardIsNotCreated() async throws {
        let context = try makeInMemoryModelContext()
        let essay = insertItem("The Myth of Sisyphus", in: context)
        try context.save()
        let conversationID = UUID()
        let tools = KnowledgeBaseTools(modelContext: context, conversationID: conversationID)

        let result = await tools.fulfill(
            toolName: "create_board",
            args: ["board_name": "Absurdism", "item_titles": "\(essay.id.uuidString), Missing Title"]
        )

        #expect(result?.contains("NOT been created") == true)
        #expect(result?.contains("waiting for the user's confirmation") == true)
        let boards: [Board] = context.fetchAll()
        #expect(boards.isEmpty)
        #expect(essay.boards.isEmpty)

        let proposal = try #require(tools.boardProposal)
        #expect(proposal.boardName == "Absurdism")
        #expect(proposal.itemIDs == [essay.id])
        #expect(proposal.itemTitles == ["The Myth of Sisyphus"])
        #expect(proposal.unmatchedTitles == ["Missing Title"])
        #expect(proposal.conversationID == conversationID)
    }

    @Test func toolListsAnItemOnceWhenReferencedTwice() async throws {
        let context = try makeInMemoryModelContext()
        let essay = insertItem("The Myth of Sisyphus", in: context)
        try context.save()
        let tools = KnowledgeBaseTools(modelContext: context, conversationID: UUID())

        _ = await tools.fulfill(
            toolName: "create_board",
            args: ["board_name": "Absurdism", "item_titles": "\(essay.id.uuidString), The Myth of Sisyphus"]
        )

        #expect(tools.boardProposal?.itemIDs == [essay.id])
    }

    @Test func toolRefusesADuplicateBoardName() async throws {
        let context = try makeInMemoryModelContext()
        context.insert(Board(title: "Research"))
        let item = insertItem("Filed thought", in: context)
        try context.save()
        let tools = KnowledgeBaseTools(modelContext: context, conversationID: UUID())

        let result = await tools.fulfill(
            toolName: "create_board",
            args: ["board_name": "research", "item_titles": item.title]
        )

        #expect(result?.contains("already exists") == true)
        #expect(tools.boardProposal == nil)
        #expect(item.boards.isEmpty)
    }

    @Test func toolRequiresABoardName() async throws {
        let context = try makeInMemoryModelContext()
        let tools = KnowledgeBaseTools(modelContext: context, conversationID: UUID())

        let result = await tools.fulfill(toolName: "create_board", args: ["board_name": "   "])

        #expect(result?.hasPrefix("Error") == true)
        #expect(tools.boardProposal == nil)
    }

    // MARK: - Pending proposal

    @Test func aTurnLeavesTheProposalPendingWithoutWriting() async throws {
        let context = try makeInMemoryModelContext()
        let item = insertItem("Filed thought", in: context)
        try context.save()

        let (service, conversation) = await propose(boardName: "Research", itemTitles: item.title, context: context)

        let boards: [Board] = context.fetchAll()
        #expect(boards.isEmpty)
        #expect(service.pendingBoardProposal(for: conversation)?.boardName == "Research")
    }

    @Test func proposalIsHiddenDuringAReply() async throws {
        let context = try makeInMemoryModelContext()
        let (service, conversation) = await propose(boardName: "Research", itemTitles: "", context: context)

        service.isGenerating = true

        #expect(service.pendingBoardProposal(for: conversation) == nil)
    }

    @Test func proposalIsVisibleToOtherServiceInstances() async throws {
        let context = try makeInMemoryModelContext()
        let (_, conversation) = await propose(boardName: "Research", itemTitles: "", context: context)

        // Chat views hold their own service, often not the one that ran the turn.
        let viewService = DialecticsService(provider: ScriptedProvider(responses: []))

        #expect(viewService.pendingBoardProposal(for: conversation)?.boardName == "Research")
    }

    @Test func aNewProposalReplacesThePendingOneInThatConversationOnly() async throws {
        let context = try makeInMemoryModelContext()
        let (service, conversation) = await propose(boardName: "First", itemTitles: "", context: context)
        let (_, other) = await propose(boardName: "Other", itemTitles: "", context: context)

        let secondCall = LLMToolCall(
            id: "call_2",
            name: "create_board",
            argumentsJSON: #"{"board_name": "Second", "item_titles": ""}"#
        )
        let replacing = DialecticsService(provider: ScriptedProvider(responses: [
            LLMChatResponse(content: nil, toolCalls: [secondCall], inputTokens: 1, outputTokens: 1),
            LLMChatResponse(content: "Changed it.", toolCalls: [], inputTokens: 1, outputTokens: 1),
        ]))
        _ = await replacing.sendMessage(userText: "Rename it.", conversation: conversation, context: context)

        #expect(service.pendingBoardProposal(for: conversation)?.boardName == "Second")
        #expect(service.pendingBoardProposal(for: other)?.boardName == "Other")
    }

    // MARK: - Confirm

    @Test func confirmCreatesTheBoardAndAssignsItems() async throws {
        let context = try makeInMemoryModelContext()
        let first = insertItem("First thought", in: context)
        let second = insertItem("Second thought", in: context)
        try context.save()
        let provider = proposingProvider(boardName: "Research", itemTitles: "First thought, Second thought")
        let (service, conversation) = await propose(
            boardName: "Research",
            itemTitles: "",
            provider: provider,
            context: context
        )
        let requestsBeforeConfirm = await provider.requests.count

        let board = try #require(service.confirmBoardProposal(for: conversation, context: context))

        let boards: [Board] = context.fetchAll()
        #expect(boards.map(\.id) == [board.id])
        #expect(board.title == "Research")
        #expect(Set(board.items.map(\.id)) == [first.id, second.id])
        #expect(first.boards.map(\.id) == [board.id])
        #expect(second.boards.map(\.id) == [board.id])

        #expect(service.pendingBoardProposal(for: conversation) == nil)
        #expect(conversation.visibleMessages.last?.role == .assistant)
        #expect(conversation.visibleMessages.last?.content == "Created board “Research” with 2 items.")
        #expect(await provider.requests.count == requestsBeforeConfirm)
    }

    @Test func confirmPromotesFeedSuggestionsAndApprovesInboxItems() async throws {
        let context = try makeInMemoryModelContext()
        let suggestion = insertItem("Suggested issue", in: context)
        suggestion.status = .inbox
        suggestion.isFeedSuggestion = true
        let pending = insertItem("Pending note", in: context)
        pending.status = .inbox
        try context.save()
        #expect(suggestion.isFeedSuggestion)

        let (service, conversation) = await propose(
            boardName: "Research",
            itemTitles: "Suggested issue, Pending note",
            context: context
        )
        service.confirmBoardProposal(for: conversation, context: context)

        #expect(!suggestion.isFeedSuggestion)
        #expect(suggestion.status == .active)
        #expect(pending.status == .active)
    }

    @Test func confirmSkipsItemsDeletedSinceTheProposal() async throws {
        let context = try makeInMemoryModelContext()
        let kept = insertItem("Kept thought", in: context)
        let removed = insertItem("Removed thought", in: context)
        try context.save()
        let (service, conversation) = await propose(
            boardName: "Research",
            itemTitles: "Kept thought, Removed thought",
            context: context
        )

        context.delete(removed)
        try context.save()
        let board = try #require(service.confirmBoardProposal(for: conversation, context: context))

        #expect(board.items.map(\.id) == [kept.id])
        #expect(conversation.visibleMessages.last?.content == "Created board “Research” with 1 item.")
    }

    @Test func confirmRefusesANameTakenSinceTheProposal() async throws {
        let context = try makeInMemoryModelContext()
        let item = insertItem("Filed thought", in: context)
        try context.save()
        let (service, conversation) = await propose(boardName: "Research", itemTitles: item.title, context: context)

        context.insert(Board(title: "research"))
        try context.save()
        let board = service.confirmBoardProposal(for: conversation, context: context)

        #expect(board == nil)
        let boards: [Board] = context.fetchAll()
        #expect(boards.count == 1)
        #expect(item.boards.isEmpty)
        #expect(service.pendingBoardProposal(for: conversation) == nil)
        #expect(conversation.visibleMessages.last?.content.contains("already exists") == true)
    }

    @Test func confirmingTwiceCreatesOneBoard() async throws {
        let context = try makeInMemoryModelContext()
        let (service, conversation) = await propose(boardName: "Research", itemTitles: "", context: context)

        service.confirmBoardProposal(for: conversation, context: context)
        let messageCount = conversation.messages.count
        service.confirmBoardProposal(for: conversation, context: context)

        let boards: [Board] = context.fetchAll()
        #expect(boards.count == 1)
        #expect(conversation.messages.count == messageCount)
    }

    // MARK: - Decline

    @Test func declineWritesNothingAndClearsTheProposal() async throws {
        let context = try makeInMemoryModelContext()
        let item = insertItem("Filed thought", in: context)
        try context.save()
        let provider = proposingProvider(boardName: "Research", itemTitles: item.title)
        let (service, conversation) = await propose(
            boardName: "Research",
            itemTitles: "",
            provider: provider,
            context: context
        )
        let requestsBeforeDecline = await provider.requests.count

        service.declineBoardProposal(for: conversation, context: context)

        let boards: [Board] = context.fetchAll()
        #expect(boards.isEmpty)
        #expect(item.boards.isEmpty)
        #expect(service.pendingBoardProposal(for: conversation) == nil)
        #expect(conversation.visibleMessages.last?.content == "Board not created.")
        #expect(await provider.requests.count == requestsBeforeDecline)
    }

    // MARK: - Persistence

    private func isolatedDefaults() -> UserDefaults {
        let name = "ChatBoardProposalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aPendingProposalSurvivesARelaunchAnchoredToItsReply() async throws {
        let context = try makeInMemoryModelContext()
        let item = insertItem("Filed thought", in: context)
        try context.save()

        let (_, conversation) = await propose(boardName: "Research", itemTitles: item.title, context: context)
        let reply = try #require(conversation.visibleMessages.last)
        #expect(reply.role == .assistant)

        // A fresh store over the same defaults is what a relaunch sees.
        let relaunched = BoardProposalStore()
        let proposal = try #require(relaunched.proposal(for: conversation.id))
        #expect(proposal.boardName == "Research")
        #expect(proposal.itemIDs == [item.id])
        #expect(proposal.messageID == reply.id)

        let afterRelaunch = DialecticsService(provider: ScriptedProvider(responses: []), boardProposals: relaunched)
        let board = try #require(afterRelaunch.confirmBoardProposal(for: conversation, context: context))
        #expect(board.items.map(\.id) == [item.id])
        #expect(BoardProposalStore().proposal(for: conversation.id) == nil)
    }

    @Test func storeKeepsOnePendingProposalPerConversationAndTakesItOnce() {
        let defaults = isolatedDefaults()
        let store = BoardProposalStore(defaults: defaults)
        let conversationID = UUID()
        let otherID = UUID()
        func proposal(_ name: String, in id: UUID) -> BoardProposal {
            BoardProposal(boardName: name, itemIDs: [UUID()], itemTitles: ["A"], unmatchedTitles: [], conversationID: id)
        }

        store.set(proposal("First", in: conversationID))
        store.set(proposal("Second", in: conversationID))
        store.set(proposal("Other", in: otherID))

        let reloaded = BoardProposalStore(defaults: defaults)
        #expect(reloaded.proposal(for: conversationID)?.boardName == "Second")
        #expect(reloaded.take(for: conversationID)?.boardName == "Second")
        #expect(reloaded.take(for: conversationID) == nil)
        #expect(store.proposal(for: conversationID) == nil)

        store.remove(for: otherID)
        #expect(BoardProposalStore(defaults: defaults).proposal(for: otherID) == nil)
    }

    @Test func deletingAConversationDiscardsItsProposal() async throws {
        let context = try makeInMemoryModelContext()
        let (service, conversation) = await propose(boardName: "Research", itemTitles: "", context: context)
        #expect(service.pendingBoardProposal(for: conversation) != nil)

        let viewModel = DialecticalChatViewModel(modelContext: context)
        let binding = Binding<Conversation?>.constant(conversation)
        let conversationID = conversation.id
        viewModel.deleteConversation(conversation, selectedConversation: binding, conversations: [conversation])

        #expect(BoardProposalStore.shared.proposal(for: conversationID) == nil)
    }

    // MARK: - Stored system prompts

    @Test func olderConversationsGetTheCurrentToolWording() async throws {
        let context = try makeInMemoryModelContext()
        let provider = ScriptedProvider(responses: [
            LLMChatResponse(content: "Hello.", toolCalls: [], inputTokens: 1, outputTokens: 1),
        ])
        let service = DialecticsService(provider: provider)
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil,
            context: context
        )
        let storedPrompt = try #require(conversation.messages.first(where: { $0.role == .system }))
        storedPrompt.content = """
        You are a thinking partner.

        You have access to the user's knowledge base. Available tools:
        {"tool_call": {"name": "create_synthesis", "args": {}}}
        {"tool_call": {"name": "create_board", "args": {}}}
        Create a new board and assign the listed items to it.
        """

        _ = await service.sendMessage(userText: "Hi", conversation: conversation, context: context)

        let systemTurn = await provider.requests.first?.first(where: { $0.role == "system" })
        #expect(systemTurn?.content.contains("You are a thinking partner.") == true)
        #expect(systemTurn?.content.contains("\"tool_call\"") == false)
        #expect(systemTurn?.content.contains("create_synthesis") == false)
    }
}
