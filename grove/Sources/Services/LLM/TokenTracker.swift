import Foundation

/// Records every LLM call with timestamp, service name, token counts, and model.
/// Persists entries in UserDefaults as JSON. Provides per-service breakdowns and optional budget limit.
@MainActor
final class TokenTracker {
    static let shared = TokenTracker()

    private static let entriesKey = "grove.tokenTracker.entries"
    private static let budgetEnabledKey = "grove.tokenTracker.budgetEnabled"
    private static let monthlyBudgetKey = "grove.tokenTracker.monthlyBudget"

    /// A single recorded LLM call.
    struct Entry: Codable, Sendable {
        let timestamp: Date
        let service: String
        let inputTokens: Int
        let outputTokens: Int
        let model: String

        var totalTokens: Int { inputTokens + outputTokens }
    }

    /// Aggregated usage for a single service.
    struct ServiceUsage: Identifiable {
        let service: String
        let inputTokens: Int
        let outputTokens: Int
        var totalTokens: Int { inputTokens + outputTokens }
        var id: String { service }

        /// Settings label for the service name recorded with each call.
        var displayName: String { TokenTracker.displayName(forService: service) }

        var estimatedCost: Double {
            TokenTracker.cost(inputTokens: inputTokens, outputTokens: outputTokens)
        }
    }

    /// Labels for every service name the app records. Names left in history by
    /// retired services are split at their camelCase humps instead.
    nonisolated static func displayName(forService service: String) -> String {
        switch service {
        case "tagging": return "Auto-Tagging"
        case "overview": return "Article Overview"
        case "dialectics": return "Chat"
        case "conversationStarter": return "Conversation Starters"
        case "tensionDetection": return "Tension Detection"
        case "flashcardDraft": return "Flashcard Drafts"
        default:
            var words = ""
            for character in service {
                if character.isUppercase, !words.isEmpty { words.append(" ") }
                words.append(character)
            }
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    /// Groq kimi-k2 pricing per million tokens.
    nonisolated static let inputCostPerMillion = 1.00
    nonisolated static let outputCostPerMillion = 3.00

    nonisolated static func cost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(inputTokens) / 1_000_000.0 * inputCostPerMillion
            + Double(outputTokens) / 1_000_000.0 * outputCostPerMillion
    }

    private(set) var entries: [Entry] = []

    var budgetEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.budgetEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Self.budgetEnabledKey) }
    }

    /// Monthly budget in tokens (default: 1,000,000).
    var monthlyBudget: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: Self.monthlyBudgetKey)
            return val > 0 ? val : 1_000_000
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.monthlyBudgetKey) }
    }

    private init() {
        loadEntries()
    }

    // MARK: - Recording

    /// Record a single LLM call.
    func record(service: String, inputTokens: Int, outputTokens: Int, model: String) {
        let entry = Entry(
            timestamp: Date(),
            service: service,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model
        )
        entries.append(entry)
        saveEntries()

        // Also update the legacy LLMServiceConfig counters for backwards compatibility
        LLMServiceConfig.recordUsage(inputTokens: inputTokens, outputTokens: outputTokens)
    }

    // MARK: - Queries

    var totalInputTokens: Int {
        entries.reduce(0) { $0 + $1.inputTokens }
    }

    var totalOutputTokens: Int {
        entries.reduce(0) { $0 + $1.outputTokens }
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// Estimated cost from per-direction pricing.
    var estimatedCost: Double {
        Self.cost(inputTokens: totalInputTokens, outputTokens: totalOutputTokens)
    }

    /// Tokens used in the current calendar month.
    var currentMonthTokens: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return entries
            .filter { $0.timestamp >= startOfMonth }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// Whether the monthly budget has been exceeded.
    var isBudgetExceeded: Bool {
        budgetEnabled && currentMonthTokens >= monthlyBudget
    }

    /// Per-service aggregated usage, sorted descending by total tokens.
    var usageByService: [ServiceUsage] {
        var dict: [String: (input: Int, output: Int)] = [:]
        for entry in entries {
            let existing = dict[entry.service, default: (0, 0)]
            dict[entry.service] = (existing.input + entry.inputTokens, existing.output + entry.outputTokens)
        }
        return dict.map { ServiceUsage(service: $0.key, inputTokens: $0.value.input, outputTokens: $0.value.output) }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    /// Total number of LLM calls recorded.
    var callCount: Int { entries.count }

    // MARK: - Reset

    func resetAll() {
        entries = []
        saveEntries()
        LLMServiceConfig.resetUsage()
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: Self.entriesKey) else { return }
        entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.entriesKey)
    }
}
