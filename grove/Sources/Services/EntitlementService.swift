import Foundation

enum SubscriptionTier: String, Codable, Sendable, CaseIterable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
}

// MARK: - Metered Usage

struct MeteredUsage: Codable {
    var count: Int
    var monthKey: String  // "yyyy-MM"
}

enum MeteredFeature: String, CaseIterable, Sendable {
    case dialectics
    case reflectionPrompts
    case autoTagging
    case connectionSuggestions
    case synthesis

    var freeLimit: Int {
        switch self {
        case .dialectics: return 6
        case .reflectionPrompts: return 3
        case .autoTagging: return 10
        case .connectionSuggestions: return 5
        case .synthesis: return 1
        }
    }

    var displayName: String {
        switch self {
        case .dialectics: return "Dialectics"
        case .reflectionPrompts: return "Reflection Prompts"
        case .autoTagging: return "Auto-Tagging"
        case .connectionSuggestions: return "Connection Suggestions"
        case .synthesis: return "Synthesis"
        }
    }
}

enum ProFeature: String, CaseIterable, Sendable, Identifiable {
    case automations
    case batchActions
    case savedWorkflows
    case sync
    case fullHistory
    case smartRouting
    case dialectics
    case reflectionPrompts
    case autoTagging
    case connectionSuggestions
    case synthesis
    case weeklyDigest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automations: return "Automations"
        case .batchActions: return "Batch Actions"
        case .savedWorkflows: return "Saved Workflows"
        case .sync: return "Cross-device Sync"
        case .fullHistory: return "Full History"
        case .smartRouting: return "Smart Routing"
        case .dialectics: return "Unlimited Dialectics"
        case .reflectionPrompts: return "AI Reflection Prompts"
        case .autoTagging: return "Auto-Tagging"
        case .connectionSuggestions: return "Connection Suggestions"
        case .synthesis: return "AI Synthesis"
        case .weeklyDigest: return "Weekly Digest"
        }
    }

    var summary: String {
        switch self {
        case .automations: return "Run recurring workflows with less manual overhead."
        case .batchActions: return "Apply actions across multiple items in fewer steps."
        case .savedWorkflows: return "Save and reuse repeatable high-value workflows."
        case .sync: return "Continue work seamlessly across devices."
        case .fullHistory: return "Search and revisit complete conversation history."
        case .smartRouting: return "On-device first with automatic cloud fallback."
        case .dialectics: return "Unlimited AI conversation sessions."
        case .reflectionPrompts: return "AI-generated reflection prompts."
        case .autoTagging: return "AI tags, summaries, and board placement."
        case .connectionSuggestions: return "AI-suggested item connections."
        case .synthesis: return "AI-generated cross-item synthesis."
        case .weeklyDigest: return "AI weekly learning summaries."
        }
    }
}

struct EntitlementState: Codable, Sendable {
    var tier: SubscriptionTier
    var isTrialActive: Bool
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var renewalDate: Date?
    var updatedAt: Date

    init(
        tier: SubscriptionTier = .free,
        isTrialActive: Bool = false,
        trialStartedAt: Date? = nil,
        trialEndsAt: Date? = nil,
        renewalDate: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.tier = tier
        self.isTrialActive = isTrialActive
        self.trialStartedAt = trialStartedAt
        self.trialEndsAt = trialEndsAt
        self.renewalDate = renewalDate
        self.updatedAt = updatedAt
    }
}

@MainActor
@Observable
final class EntitlementService {
    static let shared = EntitlementService()

    nonisolated private static let stateKey = "grove.monetization.entitlementState"
    private let defaults: UserDefaults

    private(set) var state: EntitlementState

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.state = Self.loadState(from: defaults) ?? EntitlementState()
        refreshTrialState()
    }

    var tier: SubscriptionTier {
        state.tier
    }

    var isPro: Bool {
        tier == .pro
    }

    var isTrialActive: Bool {
        state.isTrialActive
    }

    var trialEndsAt: Date? {
        state.trialEndsAt
    }

    func hasAccess(to feature: ProFeature) -> Bool {
        switch feature {
        case .automations, .batchActions, .savedWorkflows, .sync, .fullHistory, .smartRouting,
             .dialectics, .reflectionPrompts, .autoTagging, .connectionSuggestions, .synthesis, .weeklyDigest:
            return isPro
        }
    }

    // MARK: - Metered Usage

    private static let usageKeyPrefix = "grove.usage."

    private static var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    /// Returns true if the user can use this metered feature (Pro = always, Free = under limit).
    func canUse(_ feature: MeteredFeature) -> Bool {
        if isPro { return true }
        return usageCount(for: feature) < feature.freeLimit
    }

    /// Records one use of a metered feature. No-op if Pro.
    func recordUse(_ feature: MeteredFeature) {
        guard !isPro else { return }
        var usage = loadUsage(for: feature)
        let monthKey = Self.currentMonthKey
        if usage.monthKey != monthKey {
            usage = MeteredUsage(count: 0, monthKey: monthKey)
        }
        usage.count += 1
        saveUsage(usage, for: feature)
    }

    /// Returns remaining free uses for this feature. Returns Int.max if Pro.
    func remaining(_ feature: MeteredFeature) -> Int {
        if isPro { return Int.max }
        let used = usageCount(for: feature)
        return max(0, feature.freeLimit - used)
    }

    private func usageCount(for feature: MeteredFeature) -> Int {
        let usage = loadUsage(for: feature)
        guard usage.monthKey == Self.currentMonthKey else { return 0 }
        return usage.count
    }

    private func loadUsage(for feature: MeteredFeature) -> MeteredUsage {
        let key = Self.usageKeyPrefix + feature.rawValue
        guard let data = defaults.data(forKey: key),
              let usage = try? JSONDecoder().decode(MeteredUsage.self, from: data) else {
            return MeteredUsage(count: 0, monthKey: Self.currentMonthKey)
        }
        return usage
    }

    private func saveUsage(_ usage: MeteredUsage, for feature: MeteredFeature) {
        let key = Self.usageKeyPrefix + feature.rawValue
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: key)
    }

    func startTrial(days: Int = 14) {
        let start = Date.now
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)
        updateState(
            EntitlementState(
                tier: .pro,
                isTrialActive: true,
                trialStartedAt: start,
                trialEndsAt: end,
                renewalDate: end,
                updatedAt: .now
            )
        )
    }

    func activatePro(renewalDate: Date? = nil) {
        updateState(
            EntitlementState(
                tier: .pro,
                isTrialActive: false,
                trialStartedAt: state.trialStartedAt,
                trialEndsAt: state.trialEndsAt,
                renewalDate: renewalDate,
                updatedAt: .now
            )
        )
    }

    func downgradeToFree() {
        updateState(
            EntitlementState(
                tier: .free,
                isTrialActive: false,
                trialStartedAt: nil,
                trialEndsAt: nil,
                renewalDate: nil,
                updatedAt: .now
            )
        )
    }

    func refreshTrialState(referenceDate: Date = .now) {
        guard state.tier == .pro, state.isTrialActive else { return }
        guard let trialEndsAt = state.trialEndsAt else { return }
        guard trialEndsAt <= referenceDate else { return }
        downgradeToFree()
    }

    nonisolated static var currentTier: SubscriptionTier {
        guard let state = loadState(from: .standard) else { return .free }
        if state.tier == .pro, state.isTrialActive, let trialEndsAt = state.trialEndsAt, trialEndsAt <= .now {
            return .free
        }
        return state.tier
    }

    private func updateState(_ newState: EntitlementState) {
        state = newState
        persist(newState)
    }

    private func persist(_ state: EntitlementState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }

    private nonisolated static func loadState(from defaults: UserDefaults) -> EntitlementState? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(EntitlementState.self, from: data)
    }
}
