import Foundation
import Testing
@testable import grove

private actor StubLLMProvider: LLMProvider {
    let result: LLMCompletionResult?
    private(set) var lastError: LLMError?
    private(set) var completionCalls = 0
    private(set) var chatCalls = 0

    init(result: LLMCompletionResult?, error: LLMError? = nil) {
        self.result = result
        self.lastError = error
    }

    func complete(system: String, user: String) async -> LLMCompletionResult? {
        completionCalls += 1
        return result
    }

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        chatCalls += 1
        return result
    }
}

struct LLMProviderTests {
    private static let success = LLMCompletionResult(
        content: "fallback response",
        inputTokens: 3,
        outputTokens: 2
    )

    @Test func fallbackProviderUsesSecondaryAfterPrimaryFailure() async {
        let primary = StubLLMProvider(result: nil, error: .unavailable)
        let secondary = StubLLMProvider(result: Self.success)
        let provider = FallbackLLMProvider(primary: primary, fallback: secondary)

        let result = await provider.complete(system: "system", user: "prompt")

        #expect(result?.content == "fallback response")
        #expect(await primary.completionCalls == 1)
        #expect(await secondary.completionCalls == 1)
        #expect(await provider.lastError == nil)
    }

    @Test func fallbackProviderDoesNotRetryCancelledRequest() async {
        let primary = StubLLMProvider(result: nil, error: .cancelled)
        let secondary = StubLLMProvider(result: Self.success)
        let provider = FallbackLLMProvider(primary: primary, fallback: secondary)

        let result = await provider.completeChat(
            messages: [ChatTurn(role: "user", content: "prompt")],
            service: "test"
        )

        #expect(result == nil)
        #expect(await primary.chatCalls == 1)
        #expect(await secondary.chatCalls == 0)
        #expect(await provider.lastError == .cancelled)
    }

    @available(macOS 26, iOS 26, *)
    @Test func appleChatPreparationPreservesRolesWithoutReplayingAssistant() {
        let prepared = AppleIntelligenceProvider.prepareChat([
            ChatTurn(role: "system", content: "Be concise."),
            ChatTurn(role: "system", content: "Use citations."),
            ChatTurn(role: "user", content: "First question"),
            ChatTurn(role: "assistant", content: "First answer"),
            ChatTurn(role: "user", content: "Follow-up question"),
        ])

        #expect(prepared?.instructions == "Be concise.\n\nUse citations.")
        #expect(prepared?.history.map(\.role) == ["user", "assistant"])
        #expect(prepared?.history.map(\.content) == ["First question", "First answer"])
        #expect(prepared?.prompt == "Follow-up question")
    }

    @available(macOS 26, iOS 26, *)
    @Test func appleChatPreparationRetainsSeededAssistantOpeningAsContext() {
        let prepared = AppleIntelligenceProvider.prepareChat([
            ChatTurn(role: "system", content: "Challenge assumptions."),
            ChatTurn(role: "assistant", content: "Which premise should we examine?"),
            ChatTurn(role: "user", content: "The premise about incentives."),
        ])

        #expect(prepared?.instructions.contains("Previous assistant message:") == true)
        #expect(prepared?.instructions.contains("Which premise should we examine?") == true)
        #expect(prepared?.history.isEmpty == true)
        #expect(prepared?.prompt == "The premise about incentives.")
    }
}
