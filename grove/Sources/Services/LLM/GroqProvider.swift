import Foundation

/// LLM provider that calls the Groq API (OpenAI-compatible format).
/// Uses moonshotai/kimi-k2-instruct by default.
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

        let config = (
            apiKey: LLMServiceConfig.apiKey,
            model: LLMServiceConfig.model,
            baseURL: LLMServiceConfig.baseURL
        )

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

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

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

        let config = (
            apiKey: LLMServiceConfig.apiKey,
            model: LLMServiceConfig.model,
            baseURL: LLMServiceConfig.baseURL
        )

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

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

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
            } catch {
                continue
            }
        }

        lastError = .networkError
        return nil
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data, serviceName: String?) async -> LLMCompletionResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
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
