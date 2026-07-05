import Foundation

/// Tries an on-device provider first and uses cloud only when the first provider
/// cannot produce a result. Cancellation and budget failures do not trigger a
/// second request.
actor FallbackLLMProvider: LLMProvider {
    private let primary: LLMProvider
    private let fallback: LLMProvider
    private(set) var lastError: LLMError?

    init(primary: LLMProvider, fallback: LLMProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func complete(system: String, user: String) async -> LLMCompletionResult? {
        await run(
            primaryCall: { await self.primary.complete(system: system, user: user) },
            fallbackCall: { await self.fallback.complete(system: system, user: user) }
        )
    }

    func complete(system: String, user: String, service: String) async -> LLMCompletionResult? {
        await run(
            primaryCall: {
                await self.primary.complete(system: system, user: user, service: service)
            },
            fallbackCall: {
                await self.fallback.complete(system: system, user: user, service: service)
            }
        )
    }

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        await run(
            primaryCall: {
                await self.primary.completeChat(messages: messages, service: service)
            },
            fallbackCall: {
                await self.fallback.completeChat(messages: messages, service: service)
            }
        )
    }

    var supportsNativeTools: Bool {
        get async {
            if await primary.supportsNativeTools { return true }
            return await fallback.supportsNativeTools
        }
    }

    func completeChat(messages: [ChatTurn], tools: [LLMToolSpec], service: String) async -> LLMChatResponse? {
        lastError = nil
        if await primary.supportsNativeTools,
           let result = await primary.completeChat(messages: messages, tools: tools, service: service) {
            return result
        }

        let primaryError = await primary.lastError
        if primaryError == .cancelled || primaryError == .budgetExceeded {
            lastError = primaryError
            return nil
        }

        if await fallback.supportsNativeTools,
           let result = await fallback.completeChat(messages: messages, tools: tools, service: service) {
            return result
        }

        lastError = await fallback.lastError ?? primaryError
        return nil
    }

    private func run(
        primaryCall: () async -> LLMCompletionResult?,
        fallbackCall: () async -> LLMCompletionResult?
    ) async -> LLMCompletionResult? {
        lastError = nil
        if let result = await primaryCall() {
            return result
        }

        let primaryError = await primary.lastError
        if primaryError == .cancelled || primaryError == .budgetExceeded {
            lastError = primaryError
            return nil
        }

        if let result = await fallbackCall() {
            return result
        }

        lastError = await fallback.lastError ?? primaryError
        return nil
    }
}
