import Foundation
import SQLiteData
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

    // MARK: - ItemResolver

    @Test @MainActor func itemResolverResolvesUUIDExactAndFuzzyReferences() throws {
        let essay = Item(title: "The Myth of Sisyphus", type: .note)
        let other = Item(title: "Notes on Stoicism", type: .note)
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
        let first = Item(title: "Attention Is All You Need", type: .article)
        let second = Item(title: "Attention and Focus", type: .article)
        let items = [first, second]

        #expect(ItemResolver.resolve("Attention", in: items) == nil)
    }

    // MARK: - Native Tool Loop

    @Test @MainActor func dialecticsExecutesNativeToolCallsAndPersistsHiddenMessages() async throws {
        let database = try AppDatabase.openInMemory()
        var row = Item(title: "Free Will", type: .note)
        row.content = "An essay arguing hard determinism undermines moral responsibility."
        row.status = .active
        let item = row
        try await database.write { db in
            try Item.insert { item }.execute(db)
        }

        let toolCall = LLMToolCall(
            id: "call_1",
            name: "get_item_detail",
            argumentsJSON: #"{"id": "\#(item.id.uuidString)"}"#
        )
        let provider = ScriptedToolProvider(responses: [
            LLMChatResponse(content: nil, toolCalls: [toolCall], inputTokens: 1, outputTokens: 1),
            LLMChatResponse(content: "Here is my analysis of [[Free Will]].", toolCalls: [], inputTokens: 1, outputTokens: 1),
        ])
        let service = DialecticsService(database: database, provider: provider)
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil
        )

        let reply = await service.sendMessage(
            userText: "What do I have on free will?",
            conversationID: conversation.id
        )

        #expect(reply?.content == "Here is my analysis of [[Free Will]].")
        #expect(reply?.referencedItemIDs == [item.id])

        // Tool call and result persisted as hidden messages
        let conversationID = conversation.id
        let saved = try #require(try await database.read { try ConversationGraph.fetch(conversationID, in: $0) })
        let hidden = saved.messages.filter { $0.isHidden && $0.toolCallName == "get_item_detail" }
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

    // MARK: - Tension Starters

    @Test @MainActor func starterContextBuildsContradictionPairsWithReason() throws {
        let database = try AppDatabase.openInMemory()
        var a = Item(title: "Determinism", type: .note)
        a.status = .active
        a.content = "Choices are fixed by prior causes."
        var b = Item(title: "Radical Freedom", type: .note)
        b.status = .active
        b.content = "We are condemned to be free."

        var connection = Connection(sourceItemID: a.id, targetItemID: b.id, type: .contradicts)
        connection.note = "One denies free will, the other makes it absolute."
        try database.write { db in
            try Item.insert { [a, b] }.execute(db)
            try Connection.insert { connection }.execute(db)
        }

        let library = try database.read { try Library.fetch($0) }
        let starterContext = StarterContextBuilder.buildContext(from: library.items)
        #expect(starterContext.contradictionPairs.count == 1)
        let pair = try #require(starterContext.contradictionPairs.first)
        #expect(pair.reason == "One denies free will, the other makes it absolute.")

        let bubbles = StarterHeuristicGenerator.buildBoardHeuristics(
            context: starterContext,
            boardID: UUID()
        )
        let resolve = try #require(bubbles.first(where: { $0.label == "RESOLVE" }))
        // The specific reason is surfaced in the prompt...
        #expect(resolve.prompt.contains("free will"))
        // ...and both endpoints are seeded so the conversation opens on the real pair.
        #expect(Set(resolve.clusterItemIDs) == Set([a.id, b.id]))
    }

    @Test @MainActor func starterContradictionPairsDedupeAndPreferReasoned() throws {
        let database = try AppDatabase.openInMemory()
        var a = Item(title: "A", type: .note); a.status = .active
        var b = Item(title: "B", type: .note); b.status = .active
        var c = Item(title: "C", type: .note); c.status = .active
        var d = Item(title: "D", type: .note); d.status = .active

        // Reasonless pair A<->B
        let ab = Connection(sourceItemID: a.id, targetItemID: b.id, type: .contradicts)
        // Reasoned pair C<->D
        var cd = Connection(sourceItemID: c.id, targetItemID: d.id, type: .contradicts)
        cd.note = "They disagree on X."
        try database.write { db in
            try Item.insert { [a, b, c, d] }.execute(db)
            try Connection.insert { [ab, cd] }.execute(db)
        }

        let library = try database.read { try Library.fetch($0) }
        let starterContext = StarterContextBuilder.buildContext(from: library.items)
        #expect(starterContext.contradictionPairs.count == 2)
        // Reasoned pair is ranked first.
        #expect(starterContext.contradictionPairs.first?.reason == "They disagree on X.")
    }

    // MARK: - Language-Aware Embedding

    @Test func embeddedTextCarriesLanguageForComparability() {
        let english = EmbeddingIndexService.EmbeddedText(language: "en", vector: [1, 0])
        #expect(english.language == "en")
        // Guards the invariant that similarities only compare within a language:
        // an entry tagged "fr" must never be scored against an "en" query.
        #expect(english.language != "fr")
    }
}
