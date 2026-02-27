import Foundation

/// Protocol for creating LLM providers — enables test injection.
protocol LLMProviderFactory: Sendable {
    func makeProvider() -> LLMProvider
}

/// Default factory that reads from LLMServiceConfig.
struct DefaultLLMProviderFactory: LLMProviderFactory {
    func makeProvider() -> LLMProvider {
        LLMServiceConfig.makeProvider()
    }
}

/// Which LLM backend to use.
enum LLMProviderType: String, CaseIterable, Sendable {
    case appleIntelligence = "appleIntelligence"
    case groq = "groq"

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .groq: return "Cloud"
        }
    }
}

/// Stores LLM service configuration in UserDefaults.
struct LLMServiceConfig: Sendable {
    struct GroqRuntimeConfig: Sendable {
        let apiKey: String
        let model: String
        let baseURL: String
        let isManaged: Bool
    }

    private static let providerTypeKey = "grove.llm.providerType"
    private static let apiKeyKey = "grove.llm.apiKey"
    private static let modelKey = "grove.llm.model"
    private static let baseURLKey = "grove.llm.baseURL"
    private static let enabledKey = "grove.llm.enabled"
    private static let smartRoutingEnabledKey = "grove.llm.smartRoutingEnabled"
    private static let totalInputTokensKey = "grove.llm.totalInputTokens"
    private static let totalOutputTokensKey = "grove.llm.totalOutputTokens"
    private static let defaultModel = "moonshotai/kimi-k2-instruct"
    private static let defaultBaseURL = "https://api.groq.com/openai/v1/chat/completions"
    private static let managedAPIKeyEnvKey = "GROVE_MANAGED_CLOUD_API_KEY"
    private static let managedModelEnvKey = "GROVE_MANAGED_CLOUD_MODEL"
    private static let managedBaseURLEnvKey = "GROVE_MANAGED_CLOUD_BASE_URL"

    static var providerType: LLMProviderType {
        get {
            let raw = UserDefaults.standard.string(forKey: providerTypeKey) ?? ""
            return LLMProviderType(rawValue: raw) ?? .appleIntelligence
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerTypeKey) }
    }

    /// Whether Apple Intelligence is available on this OS version and hardware.
    static var isAppleIntelligenceSupported: Bool {
        if #available(macOS 26, iOS 26, *) {
            return AppleIntelligenceProvider.isAvailable
        }
        return false
    }

    /// The effective provider type, accounting for OS availability.
    /// Falls back to Groq if Apple Intelligence is selected but unsupported.
    static var effectiveProviderType: LLMProviderType {
        if providerType == .appleIntelligence && !isAppleIntelligenceSupported {
            return .groq
        }
        return providerType
    }

    /// Whether build policy allows user-managed BYO cloud configuration.
    static var isBYOAllowed: Bool {
        BuildFlags.isBYOEnabled
    }

    /// Factory that creates the currently selected provider.
    static func makeProvider() -> LLMProvider {
        enforceBuildPolicy()
        switch effectiveProviderType {
        case .appleIntelligence:
            if #available(macOS 26, iOS 26, *) {
                return AppleIntelligenceProvider()
            }
            return GroqProvider()
        case .groq:
            return GroqProvider()
        }
    }

    static var apiKey: String {
        get {
            enforceBuildPolicy()
            if isBYOAllowed {
                let stored = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
                if !stored.isEmpty { return stored }
                return envFileValue(forKey: "GROQ_API_KEY") ?? ""
            }
            return envFileValue(forKey: "GROQ_API_KEY") ?? ""
        }
        set {
            if isBYOAllowed {
                UserDefaults.standard.set(newValue, forKey: apiKeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: apiKeyKey)
            }
        }
    }

    /// Reads a value from the .env file at the project root (bundle resource fallback).
    private static func envFileValue(forKey key: String) -> String? {
        // Look for .env next to the app bundle (development convenience)
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            Bundle.main.url(forResource: ".env", withExtension: nil),
        ].compactMap { $0 }

        for url in candidates {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2, String(parts[0]).trimmingCharacters(in: .whitespaces) == key {
                    return String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    static var model: String {
        get {
            enforceBuildPolicy()
            if isBYOAllowed {
                return UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
            }
            return envFileValue(forKey: managedModelEnvKey) ?? defaultModel
        }
        set {
            if isBYOAllowed {
                UserDefaults.standard.set(newValue, forKey: modelKey)
            } else {
                UserDefaults.standard.removeObject(forKey: modelKey)
            }
        }
    }

    static var baseURL: String {
        get {
            enforceBuildPolicy()
            if isBYOAllowed {
                return UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL
            }
            return envFileValue(forKey: managedBaseURLEnvKey) ?? defaultBaseURL
        }
        set {
            if isBYOAllowed {
                UserDefaults.standard.set(newValue, forKey: baseURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: baseURLKey)
            }
        }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Pro-only routing mode that prefers on-device inference and falls back to cloud.
    /// Free users always resolve to false at runtime.
    static var smartRoutingEnabled: Bool {
        get {
            guard EntitlementService.currentTier == .pro else { return false }
            return UserDefaults.standard.object(forKey: smartRoutingEnabledKey) as? Bool ?? false
        }
        set { UserDefaults.standard.set(newValue, forKey: smartRoutingEnabledKey) }
    }

    /// Whether the service is configured and ready to use.
    static var isConfigured: Bool {
        guard isEnabled else { return false }
        switch effectiveProviderType {
        case .appleIntelligence:
            return true
        case .groq:
            return !groqRuntimeConfig().apiKey.isEmpty
        }
    }

    static func groqRuntimeConfig() -> GroqRuntimeConfig {
        enforceBuildPolicy()
        return GroqRuntimeConfig(
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            isManaged: !isBYOAllowed
        )
    }

    /// In release builds, remove locally persisted BYO overrides so runtime cannot use them.
    static func enforceBuildPolicy() {
        guard !isBYOAllowed else { return }
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
        UserDefaults.standard.removeObject(forKey: modelKey)
        UserDefaults.standard.removeObject(forKey: baseURLKey)
    }

    // MARK: - Token Usage Tracking

    static var totalInputTokens: Int {
        get { UserDefaults.standard.integer(forKey: totalInputTokensKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalInputTokensKey) }
    }

    static var totalOutputTokens: Int {
        get { UserDefaults.standard.integer(forKey: totalOutputTokensKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalOutputTokensKey) }
    }

    static var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// Estimated cost at $1.50 per million tokens (blended rate).
    static var estimatedCost: Double {
        Double(totalTokens) / 1_000_000.0 * 1.50
    }

    /// Record token usage from a completion result.
    static func recordUsage(inputTokens: Int, outputTokens: Int) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
    }

    /// Reset all token usage counters to zero.
    static func resetUsage() {
        totalInputTokens = 0
        totalOutputTokens = 0
    }
}
