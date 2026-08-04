import Foundation

/// Tries an on-device provider first and uses cloud only when the first provider
/// cannot produce a result. Cancellation and budget failures do not trigger a
/// second request.
///
/// Two named service groups invert or narrow that default: `cloudOnlyServices`
/// never reach the on-device model at all, and `cloudPreferredServices` run the
/// order backwards — cloud first, on-device as the safety net.
actor FallbackLLMProvider: LLMProvider {
    private let primary: LLMProvider
    private let fallback: LLMProvider
    private(set) var lastError: LLMError?

    /// Services that must never touch the smaller on-device model. Tension
    /// detection writes `.contradicts` connections into the graph — a wrong
    /// one is a durable false claim about the user's own material, so no
    /// answer beats a cheap answer.
    private static let cloudOnlyServices: Set<String> = ["tensionDetection"]

    /// Services that read better from the cloud but are worth having either
    /// way. A conversation starter is a suggestion the user can ignore, not a
    /// record: when the cloud can't answer — offline, no key, budget spent —
    /// an on-device starter beats an empty home screen.
    private static let cloudPreferredServices: Set<String> = ["conversationStarter"]

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
        if Self.cloudOnlyServices.contains(service) {
            lastError = nil
            if let result = await fallback.complete(system: system, user: user, service: service) {
                return result
            }
            lastError = await fallback.lastError
            return nil
        }

        if Self.cloudPreferredServices.contains(service) {
            return await runCloudPreferred(
                cloudCall: {
                    await self.fallback.complete(system: system, user: user, service: service)
                },
                onDeviceCall: {
                    await self.primary.complete(system: system, user: user, service: service)
                }
            )
        }

        return await run(
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

    /// The reverse ordering: cloud first, on-device only as a safety net.
    ///
    /// A cancelled request still stops here — the caller walked away, so
    /// there is nobody to serve a second answer to. A budget failure does
    /// *not* stop it: the on-device model costs nothing, which is exactly why
    /// it's worth reaching for when the cloud budget is spent.
    ///
    /// When both fail, the cloud error is what gets reported — "on-device AI
    /// is unavailable" explains nothing about why the preferred model didn't
    /// answer.
    private func runCloudPreferred(
        cloudCall: () async -> LLMCompletionResult?,
        onDeviceCall: () async -> LLMCompletionResult?
    ) async -> LLMCompletionResult? {
        lastError = nil
        if let result = await cloudCall() {
            return result
        }

        let cloudError = await fallback.lastError
        if cloudError == .cancelled {
            lastError = cloudError
            return nil
        }

        if let result = await onDeviceCall() {
            return result
        }

        let onDeviceError = await primary.lastError
        lastError = cloudError ?? onDeviceError
        return nil
    }
}
