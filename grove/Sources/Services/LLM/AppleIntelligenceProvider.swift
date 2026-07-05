import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM provider that uses Apple's on-device Foundation Models framework (macOS 26+).
/// Free, private, zero-config — no API key required.
/// All calls are async, non-blocking, and failure-tolerant.
/// On macOS < 26, all calls return nil (graceful degradation).
@available(macOS 26, iOS 26, *)
actor AppleIntelligenceProvider: LLMProvider {
    private(set) var lastError: LLMError?

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
        lastError = nil
        guard AppleIntelligenceProvider.isAvailable else {
            lastError = .unavailable
            return nil
        }

        do {
            let session = LanguageModelSession(
                model: .default,
                instructions: system
            )
            let response = try await session.respond(to: user)
            let content = String(response.content)
            guard !content.isEmpty else {
                lastError = .emptyResponse
                return nil
            }

            // Foundation Models in the Xcode 26 SDK does not expose public token
            // accounting. Keep this estimate isolated until the SDK provides it.
            let inputTokens = Self.estimatedTokenCount(system + user)
            let outputTokens = Self.estimatedTokenCount(content)

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
            lastError = Self.mapError(error)
            return nil
        }
    }

    // MARK: - Multi-Turn Chat

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        lastError = nil
        guard SystemLanguageModel.default.availability == .available else {
            lastError = .unavailable
            return nil
        }

        guard let request = Self.prepareChat(messages) else {
            lastError = .emptyResponse
            return nil
        }

        do {
            let session = LanguageModelSession(
                model: .default,
                transcript: Self.makeTranscript(for: request)
            )
            let response = try await session.respond(to: request.prompt)
            let content = String(response.content)
            guard !content.isEmpty else {
                lastError = .emptyResponse
                return nil
            }

            let inputText = ([request.instructions] + request.history.map(\.content) + [request.prompt])
                .joined()
            let inputTokens = Self.estimatedTokenCount(inputText)
            let outputTokens = Self.estimatedTokenCount(content)

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
            lastError = Self.mapError(error)
            return nil
        }
    }

    struct PreparedChat {
        let instructions: String
        let history: [ChatTurn]
        let prompt: String
    }

    /// Separates the prompt that should generate the next response from prior
    /// turns. Historical assistant responses become transcript responses and
    /// are never submitted as new prompts.
    static func prepareChat(_ messages: [ChatTurn]) -> PreparedChat? {
        var instructions = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")
        let conversation = messages.filter { $0.role != "system" }
        guard let promptIndex = conversation.lastIndex(where: {
            $0.role == "user" || $0.role == "tool"
        }), promptIndex == conversation.index(before: conversation.endIndex) else {
            return nil
        }

        var history = Array(conversation[..<promptIndex])
        // Grove can seed a conversation with an opening assistant message that
        // was generated in a separate session. A Foundation Models transcript
        // cannot represent that as a response without a preceding prompt, so
        // retain it as session context instead of fabricating a user turn.
        while history.first?.role == "assistant" {
            let opening = history.removeFirst().content
            let separator = instructions.isEmpty ? "" : "\n\n"
            instructions += "\(separator)Previous assistant message:\n\(opening)"
        }

        return PreparedChat(
            instructions: instructions,
            history: history,
            prompt: conversation[promptIndex].content
        )
    }

    private static func makeTranscript(for request: PreparedChat) -> Transcript {
        var entries: [Transcript.Entry] = []
        if !request.instructions.isEmpty {
            entries.append(
                .instructions(
                    Transcript.Instructions(
                        segments: [.text(.init(content: request.instructions))],
                        toolDefinitions: []
                    )
                )
            )
        }

        for turn in request.history {
            let segments: [Transcript.Segment] = [.text(.init(content: turn.content))]
            if turn.role == "assistant" {
                entries.append(.response(.init(assetIDs: [], segments: segments)))
            } else {
                entries.append(.prompt(.init(segments: segments)))
            }
        }
        return Transcript(entries: entries)
    }

    private static func estimatedTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    private static func mapError(_ error: Error) -> LLMError {
        if error is CancellationError {
            return .cancelled
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = generationError {
                return .contextWindowExceeded
            }
            if case .assetsUnavailable = generationError {
                return .unavailable
            }
        }
        return .generationFailed
    }
}
