import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM provider that uses Apple's on-device Foundation Models framework (macOS 26+).
/// Free, private, zero-config — no API key required.
/// All calls are async, non-blocking, and failure-tolerant — returns nil on any error.
/// On macOS < 26, all calls return nil (graceful degradation).
@available(macOS 26, *)
final class AppleIntelligenceProvider: LLMProvider, Sendable {

    /// Check whether the on-device model is available on this machine.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func complete(system: String, user: String) async -> LLMCompletionResult? {
        await complete(system: system, user: user, serviceName: nil)
    }

    func complete(system: String, user: String, service: String) async -> LLMCompletionResult? {
        await complete(system: system, user: user, serviceName: service)
    }

    private func complete(system: String, user: String, serviceName: String?) async -> LLMCompletionResult? {
        guard SystemLanguageModel.default.availability == .available else { return nil }

        do {
            let session = LanguageModelSession(
                model: .default,
                instructions: system
            )
            let response = try await session.respond(to: user)
            let content = String(response.content)
            guard !content.isEmpty else { return nil }

            // Estimate tokens (~4 chars per token heuristic)
            let inputTokens = (system.count + user.count) / 4
            let outputTokens = content.count / 4

            if let serviceName {
                await MainActor.run {
                    TokenTracker.shared.record(
                        service: serviceName,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        model: "apple-intelligence"
                    )
                }
            }

            return LLMCompletionResult(
                content: content,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
        } catch {
            return nil
        }
    }

    // MARK: - Multi-Turn Chat

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        guard SystemLanguageModel.default.availability == .available else { return nil }

        do {
            // Extract system instruction from first system message
            let systemInstruction = messages.first { $0.role == "system" }?.content ?? ""
            let session = LanguageModelSession(
                model: .default,
                instructions: systemInstruction
            )

            // Replay non-system messages sequentially to build conversation history
            let conversationMessages = messages.filter { $0.role != "system" }
            var lastContent: String?
            var totalInputChars = systemInstruction.count

            for message in conversationMessages {
                totalInputChars += message.content.count
                let response = try await session.respond(to: message.content)
                lastContent = String(response.content)
            }

            guard let content = lastContent, !content.isEmpty else { return nil }

            let inputTokens = totalInputChars / 4
            let outputTokens = content.count / 4

            await MainActor.run {
                TokenTracker.shared.record(
                    service: service,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    model: "apple-intelligence"
                )
            }

            return LLMCompletionResult(
                content: content,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
        } catch {
            return nil
        }
    }
}
