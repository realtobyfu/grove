import Foundation
import SwiftData
import Testing
@testable import grove

/// Scripted provider that exercises the native tool-calling path.
private actor ScriptedToolProvider: LLMProvider {
    private var responses: [LLMChatResponse]
    private(set) var toolRequests: [[ChatTurn]] = []
    private(set) var lastError: LLMError?

    init(responses: [LLMChatResponse]) {
        self.responses = responses
    }

    var supportsNativeTools: Bool { true }

    func complete(system: String, user: String) async -> LLMCompletionResult? { nil }

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        LLMCompletionResult(content: "untooled fallback", inputTokens: 0, outputTokens: 0)
    }

    func completeChat(messages: [ChatTurn], tools: [LLMToolSpec], service: String) async -> LLMChatResponse? {
        toolRequests.append(messages)
        guard !responses.isEmpty else { return nil }
        return responses.removeFirst()
    }
}

struct AgenticToolTests {

    @MainActor
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "AgenticToolTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - ItemResolver

    @Test @MainActor func itemResolverResolvesUUIDExactAndFuzzyReferences() throws {
        let context = try makeInMemoryModelContext()
        let essay = Item(title: "The Myth of Sisyphus", type: .note)
        let other = Item(title: "Notes on Stoicism", type: .note)
        context.insert(essay)
        context.insert(other)
        let items = [essay, other]

        #expect(ItemResolver.resolve(essay.id.uuidString, in: items)?.id == essay.id)
        #expect(ItemResolver.resolve("the myth of sisyphus", in: items)?.id == essay.id)
        // Normalized: punctuation and casing differences
        #expect(ItemResolver.resolve("The Myth of Sisyphus!", in: items)?.id == essay.id)
        // Unique substring
        #expect(ItemResolver.resolve("Myth of Sisyphus", in: items)?.id == essay.id)
        // No match
        #expect(ItemResolver.resolve("Unrelated Title", in: items) == nil)
    }

    @Test @MainActor func itemResolverRejectsAmbiguousSubstringMatches() throws {
        let context = try makeInMemoryModelContext()
        let first = Item(title: "Attention Is All You Need", type: .article)
        let second = Item(title: "Attention and Focus", type: .article)
        context.insert(first)
        context.insert(second)

        #expect(ItemResolver.resolve("Attention", in: [first, second]) == nil)
    }

    // MARK: - Native Tool Loop

    @Test @MainActor func dialecticsExecutesNativeToolCallsAndPersistsHiddenMessages() async throws {
        let context = try makeInMemoryModelContext()
        let item = Item(title: "Free Will", type: .note)
        item.content = "An essay arguing hard determinism undermines moral responsibility."
        item.status = .active
        context.insert(item)
        try context.save()

        let toolCall = LLMToolCall(
            id: "call_1",
            name: "get_item_detail",
            argumentsJSON: #"{"id": "\#(item.id.uuidString)"}"#
        )
        let provider = ScriptedToolProvider(responses: [
            LLMChatResponse(content: nil, toolCalls: [toolCall], inputTokens: 1, outputTokens: 1),
            LLMChatResponse(content: "Here is my analysis of [[Free Will]].", toolCalls: [], inputTokens: 1, outputTokens: 1),
        ])
        let service = DialecticsService(provider: provider)
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil,
            context: context
        )

        let reply = await service.sendMessage(
            userText: "What do I have on free will?",
            conversation: conversation,
            context: context
        )

        #expect(reply?.content == "Here is my analysis of [[Free Will]].")
        #expect(reply?.referencedItemIDs == [item.id])

        // Tool call and result persisted as hidden messages
        let hidden = conversation.messages.filter { $0.isHidden && $0.toolCallName == "get_item_detail" }
        #expect(hidden.count == 2)

        // Second request carried the tool result turn linked by call ID
        let secondRequest = await provider.toolRequests.last
        let toolTurn = secondRequest?.first(where: { $0.role == "tool" })
        #expect(toolTurn?.toolCallID == "call_1")
        #expect(toolTurn?.content.contains("Free Will") == true)

        // Native path strips the prompt-based tool instructions from the system turn
        let systemTurn = secondRequest?.first(where: { $0.role == "system" })
        #expect(systemTurn?.content.contains("\"tool_call\"") == false)
    }

    // MARK: - LLMToolCall

    @Test func toolCallStringArgumentsStringifiesMixedTypes() {
        let call = LLMToolCall(
            id: "c1",
            name: "search_items",
            argumentsJSON: #"{"query": "stoicism", "limit": 5}"#
        )
        #expect(call.stringArguments["query"] == "stoicism")
        #expect(call.stringArguments["limit"] == "5")
    }

    // MARK: - Embedding Index Helpers

    @Test func cosineSimilarityIdentifiesIdenticalAndOrthogonalVectors() {
        #expect(abs(EmbeddingIndexService.cosineSimilarity([1, 0, 1], [1, 0, 1]) - 1.0) < 0.0001)
        #expect(abs(EmbeddingIndexService.cosineSimilarity([1, 0], [0, 1])) < 0.0001)
        #expect(EmbeddingIndexService.cosineSimilarity([], []) == 0)
        #expect(EmbeddingIndexService.cosineSimilarity([1, 2], [1, 2, 3]) == 0)
    }

    @Test func stableHashIsDeterministicAndSensitiveToContent() {
        let a = EmbeddingIndexService.stableHash("the same text")
        let b = EmbeddingIndexService.stableHash("the same text")
        let c = EmbeddingIndexService.stableHash("different text")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Tension Detection

    @Test func tensionPairKeyIsOrderIndependent() {
        let a = UUID()
        let b = UUID()
        #expect(TensionDetectionService.pairKey(a, b) == TensionDetectionService.pairKey(b, a))
    }
}
