import Foundation

/// LLM provider that calls the Groq API (OpenAI-compatible format).
/// All calls are async, non-blocking, and failure-tolerant — returns nil on any error.
actor GroqProvider: LLMProvider {
    private let session: URLSession
    private let maxRetries = 3
    private(set) var lastError: LLMError?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(system: String, user: String, service: String) async -> LLMCompletionResult? {
        await complete(system: system, user: user, serviceName: service)
    }

    func complete(system: String, user: String) async -> LLMCompletionResult? {
        await complete(system: system, user: user, serviceName: nil)
    }

    private func complete(system: String, user: String, serviceName: String?) async -> LLMCompletionResult? {
        lastError = nil

        // Check monthly budget limit
        let budgetExceeded = await MainActor.run { TokenTracker.shared.isBudgetExceeded }
        if budgetExceeded { lastError = .budgetExceeded; return nil }

        let config = LLMServiceConfig.groqRuntimeConfig()

        guard !config.apiKey.isEmpty else { lastError = .apiKeyMissing; return nil }
        guard let url = URL(string: config.baseURL) else { lastError = .invalidURL; return nil }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
            "max_tokens": 4096,
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            lastError = .generationFailed
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        request.timeoutInterval = 30

        // Retry with exponential backoff
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled else { lastError = .cancelled; return nil }

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else { continue }

                // Retry on server errors and rate limits
                if httpResponse.statusCode >= 500 || httpResponse.statusCode == 429 {
                    continue
                }

                guard httpResponse.statusCode == 200 else {
                    lastError = .serverError(statusCode: httpResponse.statusCode)
                    return nil
                }

                return await parseResponse(data, serviceName: serviceName)
            } catch is CancellationError {
                lastError = .cancelled
                return nil
            } catch let error as URLError where error.code == .cancelled {
                lastError = .cancelled
                return nil
            } catch {
                // Network error — retry
                continue
            }
        }

        lastError = .networkError
        return nil
    }

    // MARK: - Multi-Turn Chat

    func completeChat(messages: [ChatTurn], service: String) async -> LLMCompletionResult? {
        lastError = nil

        let budgetExceeded = await MainActor.run { TokenTracker.shared.isBudgetExceeded }
        if budgetExceeded { lastError = .budgetExceeded; return nil }

        let config = LLMServiceConfig.groqRuntimeConfig()

        guard !config.apiKey.isEmpty else { lastError = .apiKeyMissing; return nil }
        guard let url = URL(string: config.baseURL) else { lastError = .invalidURL; return nil }

        let apiMessages = messages.map { turn -> [String: String] in
            ["role": turn.role, "content": turn.content]
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "temperature": 0.5,
            "max_tokens": 4000,
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            lastError = .generationFailed
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        request.timeoutInterval = 60

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled else { lastError = .cancelled; return nil }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                if httpResponse.statusCode >= 500 || httpResponse.statusCode == 429 { continue }
                guard httpResponse.statusCode == 200 else {
                    lastError = .serverError(statusCode: httpResponse.statusCode)
                    return nil
                }
                return await parseResponse(data, serviceName: service)
            } catch is CancellationError {
                lastError = .cancelled
                return nil
            } catch let error as URLError where error.code == .cancelled {
                lastError = .cancelled
                return nil
            } catch {
                continue
            }
        }

        lastError = .networkError
        return nil
    }

    // MARK: - Native Tool Calling

    var supportsNativeTools: Bool { true }

    func completeChat(messages: [ChatTurn], tools: [LLMToolSpec], service: String) async -> LLMChatResponse? {
        lastError = nil

        let budgetExceeded = await MainActor.run { TokenTracker.shared.isBudgetExceeded }
        if budgetExceeded { lastError = .budgetExceeded; return nil }

        let config = LLMServiceConfig.groqRuntimeConfig()
        guard !config.apiKey.isEmpty else { lastError = .apiKeyMissing; return nil }
        guard let url = URL(string: config.baseURL) else { lastError = .invalidURL; return nil }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map(Self.apiMessage),
            "temperature": 0.5,
            "max_tokens": 4000,
        ]

        if !tools.isEmpty {
            body["tools"] = tools.compactMap { spec -> [String: Any]? in
                guard let paramsData = spec.parametersJSON.data(using: .utf8),
                      let params = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] else {
                    return nil
                }
                return [
                    "type": "function",
                    "function": [
                        "name": spec.name,
                        "description": spec.description,
                        "parameters": params,
                    ],
                ]
            }
            body["tool_choice"] = "auto"
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            lastError = .generationFailed
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        request.timeoutInterval = 60

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled else { lastError = .cancelled; return nil }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                if httpResponse.statusCode >= 500 || httpResponse.statusCode == 429 { continue }
                guard httpResponse.statusCode == 200 else {
                    lastError = .serverError(statusCode: httpResponse.statusCode)
                    return nil
                }
                return await parseToolResponse(data, serviceName: service)
            } catch is CancellationError {
                lastError = .cancelled
                return nil
            } catch let error as URLError where error.code == .cancelled {
                lastError = .cancelled
                return nil
            } catch {
                continue
            }
        }

        lastError = .networkError
        return nil
    }

    /// Serialize a ChatTurn into an OpenAI-compatible message dictionary,
    /// including assistant tool_calls and tool result linkage.
    private static func apiMessage(_ turn: ChatTurn) -> [String: Any] {
        var message: [String: Any] = ["role": turn.role]

        if turn.role == "tool" {
            message["content"] = turn.content
            if let toolCallID = turn.toolCallID {
                message["tool_call_id"] = toolCallID
            }
            return message
        }

        if let toolCalls = turn.toolCalls, !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.argumentsJSON],
                ] as [String: Any]
            }
            if !turn.content.isEmpty {
                message["content"] = turn.content
            }
            return message
        }

        message["content"] = turn.content
        return message
    }

    private func parseToolResponse(_ data: Data, serviceName: String) async -> LLMChatResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any]
        else {
            lastError = .emptyResponse
            return nil
        }

        let content = message["content"] as? String

        var toolCalls: [LLMToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for rawCall in rawCalls {
                guard let function = rawCall["function"] as? [String: Any],
                      let name = function["name"] as? String else { continue }
                toolCalls.append(LLMToolCall(
                    id: rawCall["id"] as? String ?? UUID().uuidString,
                    name: name,
                    argumentsJSON: function["arguments"] as? String ?? "{}"
                ))
            }
        }

        guard content?.isEmpty == false || !toolCalls.isEmpty else {
            lastError = .emptyResponse
            return nil
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0
        let model = LLMServiceConfig.model

        await MainActor.run {
            TokenTracker.shared.record(
                service: serviceName,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                model: model
            )
        }

        return LLMChatResponse(
            content: content,
            toolCalls: toolCalls,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data, serviceName: String?) async -> LLMCompletionResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty
        else {
            lastError = .emptyResponse
            return nil
        }

        // Parse token usage
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0
        let model = LLMServiceConfig.model

        // Record to TokenTracker (per-service tracking) if service name provided
        if let serviceName = serviceName {
            await MainActor.run {
                TokenTracker.shared.record(
                    service: serviceName,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    model: model
                )
            }
        } else {
            // Legacy: just update global counters
            await MainActor.run {
                LLMServiceConfig.recordUsage(inputTokens: inputTokens, outputTokens: outputTokens)
            }
        }

        return LLMCompletionResult(
            content: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
