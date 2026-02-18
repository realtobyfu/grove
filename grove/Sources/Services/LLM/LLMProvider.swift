import Foundation

/// Result from an LLM completion call, including token usage.
struct LLMCompletionResult: Sendable {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
}

/// A single turn in a multi-turn conversation for the LLM API.
struct ChatTurn: Sendable {
    let role: String   // "system", "user", "assistant", "tool"
    let content: String
}

/// Protocol for LLM service providers.
/// All implementations must be async, non-blocking, and failure-tolerant.
protocol LLMProvider: Sendable {
    /// Send a chat completion request and return the response text.
    /// Returns nil on failure — never throws to callers.
    func complete(system: String, user: String) async -> LLMCompletionResult?

    /// Send a chat completion request tagged with a service name for token tracking.
    /// Returns nil on failure — never throws to callers.
    func complete(system: String, user: String, service: String) async -> LLMCompletionResult?

    /// Multi-turn chat completion for conversational use cases.
    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult?
}

/// Categorizes LLM failure modes with user-facing messages.
enum LLMError: Sendable {
    case apiKeyMissing
    case budgetExceeded
    case invalidURL
    case networkError
    case serverError(statusCode: Int)
    case emptyResponse
    case cancelled

    var userMessage: String {
        switch self {
        case .apiKeyMissing:
            return "No API key configured. Add one in Settings > AI."
        case .budgetExceeded:
            return "Monthly token budget exceeded."
        case .invalidURL:
            return "Invalid API URL."
        case .networkError:
            return "Could not reach the AI service."
        case .serverError(let statusCode):
            return "The AI service returned an error (HTTP \(statusCode))."
        case .emptyResponse:
            return "The AI returned an empty response."
        case .cancelled:
            return "Request was cancelled."
        }
    }
}

extension LLMProvider {
    func complete(system: String, user: String, service: String) async -> LLMCompletionResult? {
        await complete(system: system, user: user)
    }

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        nil
    }
}
