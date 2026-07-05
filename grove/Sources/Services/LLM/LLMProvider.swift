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
    /// For role "tool": the ID of the tool call this turn responds to.
    var toolCallID: String?
    /// For assistant turns that requested tool calls.
    var toolCalls: [LLMToolCall]?

    init(role: String, content: String, toolCallID: String? = nil, toolCalls: [LLMToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }
}

/// A tool invocation requested by the model via native tool calling.
struct LLMToolCall: Sendable, Equatable {
    let id: String
    let name: String
    /// Raw JSON string of the arguments object.
    let argumentsJSON: String

    /// Arguments decoded into a string-keyed map with stringified values.
    var stringArguments: [String: String] {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var args: [String: String] = [:]
        for (key, value) in json {
            args[key] = "\(value)"
        }
        return args
    }
}

/// Declares a tool the model may call natively (OpenAI-compatible function spec).
struct LLMToolSpec: Sendable {
    let name: String
    let description: String
    /// JSON Schema for the arguments object, as a JSON string.
    let parametersJSON: String
}

/// Result of a tools-aware chat completion: either content, tool calls, or both.
struct LLMChatResponse: Sendable {
    let content: String?
    let toolCalls: [LLMToolCall]
    let inputTokens: Int
    let outputTokens: Int
}

/// Protocol for LLM service providers.
/// All implementations must be async, non-blocking, and failure-tolerant.
protocol LLMProvider: Sendable {
    /// The most recent provider failure, when the implementation can identify it.
    var lastError: LLMError? { get async }

    /// Send a chat completion request and return the response text.
    /// Returns nil on failure — never throws to callers.
    func complete(system: String, user: String) async -> LLMCompletionResult?

    /// Send a chat completion request tagged with a service name for token tracking.
    /// Returns nil on failure — never throws to callers.
    func complete(system: String, user: String, service: String) async -> LLMCompletionResult?

    /// Multi-turn chat completion for conversational use cases.
    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult?

    /// Whether this provider supports native (API-level) tool calling.
    var supportsNativeTools: Bool { get async }

    /// Multi-turn chat completion with native tool calling.
    /// Returns nil on failure or when the provider does not support tools.
    func completeChat(messages: [ChatTurn], tools: [LLMToolSpec], service: String) async -> LLMChatResponse?
}

/// Categorizes LLM failure modes with user-facing messages.
enum LLMError: Error, Equatable, Sendable {
    case apiKeyMissing
    case budgetExceeded
    case invalidURL
    case networkError
    case serverError(statusCode: Int)
    case emptyResponse
    case cancelled
    case unavailable
    case contextWindowExceeded
    case generationFailed

    var userMessage: String {
        switch self {
        case .apiKeyMissing:
            return "Cloud AI is unavailable."
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
        case .unavailable:
            return "On-device AI is unavailable."
        case .contextWindowExceeded:
            return "This conversation is too long for the AI model."
        case .generationFailed:
            return "The AI could not generate a response."
        }
    }
}

extension LLMProvider {
    var lastError: LLMError? {
        get async { nil }
    }

    func complete(system: String, user: String, service: String) async -> LLMCompletionResult? {
        await complete(system: system, user: user)
    }

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        nil
    }

    var supportsNativeTools: Bool {
        get async { false }
    }

    func completeChat(messages: [ChatTurn], tools: [LLMToolSpec], service: String) async -> LLMChatResponse? {
        nil
    }
}
