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

/// This month's cloud chat usage: the conversations that have sent at least
/// one message to cloud AI. A conversation counts once, at its first cloud
/// send, however many messages follow.
struct CloudConversationUsage: Codable, Equatable {
    var monthKey: String  // "yyyy-MM"
    var conversationIDs: [UUID]
    /// Uses counted before conversations were tracked by ID (the old
    /// count-at-creation `MeteredUsage`), carried into the month they belong to.
    var carriedOverCount: Int

    var usedCount: Int { conversationIDs.count + carriedOverCount }
}

/// AI features the free tier can use a limited number of times per month when
/// they run on cloud AI. On-device AI costs nothing to serve, so it is never
/// limited. Every case is enforced somewhere (`canUse` + `recordUse`); a case
/// with no call site is a ghost and must not be added back.
enum MeteredFeature: String, CaseIterable, Sendable {
    case dialectics      // DialecticsService.sendMessage (canSendCloudMessage); creation-time early gate in chat entry points
    case autoTagging     // AutoTagService

    var freeLimit: Int {
        switch self {
        case .dialectics: return 6
        case .autoTagging: return 10
        }
    }

    var displayName: String {
        switch self {
        case .dialectics: return "Chat"
        case .autoTagging: return "Auto-Tagging"
        }
    }
}

/// What Grove Pro unlocks. This list is shown on the paywall, so every case
/// must be a feature that exists and is gated on `isPro` somewhere in the app:
/// sync (SyncSettingsView), full history (chat conversation lists), smart
/// routing (AI settings) and the two metered features above.
enum ProFeature: String, CaseIterable, Sendable, Identifiable {
    case sync
    case dialectics
    case fullHistory
    case smartRouting
    case autoTagging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sync: return "Cross-device Sync"
        case .dialectics: return "Unlimited Chat"
        case .fullHistory: return "Full History"
        case .smartRouting: return "Smart Routing"
        case .autoTagging: return "Unlimited Auto-Tagging"
        }
    }

    var summary: String {
        switch self {
        case .sync: return "Your library, boards and reflections on every device, through iCloud."
        case .dialectics: return "Unlimited cloud conversations grounded in your own library. Free includes six a month, and on-device chat is never limited."
        case .fullHistory: return "Keep and search your complete conversation history."
        case .smartRouting: return "On-device AI first, with cloud AI as a fallback when it is needed."
        case .autoTagging: return "Cloud AI tags, a one-line summary and a board suggestion for every capture. Free includes ten a month, and on-device tagging is never limited."
        }
    }
}

enum SubscriptionSource: String, Codable, Sendable {
    case local
    case trial
    case storeKit
}

struct EntitlementState: Codable, Sendable {
    var tier: SubscriptionTier
    var isTrialActive: Bool
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var renewalDate: Date?
    var source: SubscriptionSource
    var updatedAt: Date

    init(
        tier: SubscriptionTier = .free,
        isTrialActive: Bool = false,
        trialStartedAt: Date? = nil,
        trialEndsAt: Date? = nil,
        renewalDate: Date? = nil,
        source: SubscriptionSource = .local,
        updatedAt: Date = .now
    ) {
        self.tier = tier
        self.isTrialActive = isTrialActive
        self.trialStartedAt = trialStartedAt
        self.trialEndsAt = trialEndsAt
        self.renewalDate = renewalDate
        self.source = source
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier = try container.decode(SubscriptionTier.self, forKey: .tier)
        isTrialActive = try container.decode(Bool.self, forKey: .isTrialActive)
        trialStartedAt = try container.decodeIfPresent(Date.self, forKey: .trialStartedAt)
        trialEndsAt = try container.decodeIfPresent(Date.self, forKey: .trialEndsAt)
        renewalDate = try container.decodeIfPresent(Date.self, forKey: .renewalDate)
        // Backward compatibility: default to .local if source key is missing
        source = (try? container.decode(SubscriptionSource.self, forKey: .source)) ?? .local
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

@MainActor
@Observable
final class EntitlementService {
    static let shared = EntitlementService()

    nonisolated private static let stateKey = "grove.monetization.entitlementState"
    private let defaults: UserDefaults
    /// Whether AI calls currently go to the cloud. Free-tier limits apply only then.
    private let usesCloudAI: () -> Bool

    private(set) var state: EntitlementState

    init(
        defaults: UserDefaults = .standard,
        usesCloudAI: @escaping () -> Bool = { LLMServiceConfig.effectiveProviderType == .groq }
    ) {
        self.defaults = defaults
        self.usesCloudAI = usesCloudAI
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

    /// Pro is all-or-nothing: every `ProFeature` unlocks together.
    func hasAccess(to feature: ProFeature) -> Bool {
        isPro
    }

    // MARK: - Metered Usage

    private static let usageKeyPrefix = "grove.usage."

    private static var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    /// True when metered features count against a monthly limit: a free user on cloud AI.
    var hasUsageLimits: Bool {
        !isPro && usesCloudAI()
    }

    /// Returns true if the user can use this metered feature. Only a free user
    /// on cloud AI has a limit; Pro and on-device AI are unlimited.
    func canUse(_ feature: MeteredFeature) -> Bool {
        guard hasUsageLimits else { return true }
        return usageCount(for: feature) < feature.freeLimit
    }

    /// Records one use of a metered feature. No-op when no limit applies.
    /// Chat is metered per conversation through `recordCloudMessage(in:)`;
    /// a `.dialectics` use recorded here counts as one untracked conversation.
    func recordUse(_ feature: MeteredFeature) {
        guard hasUsageLimits else { return }
        if feature == .dialectics {
            var usage = loadCloudConversationUsage()
            usage.carriedOverCount += 1
            saveCloudConversationUsage(usage)
            return
        }
        var usage = loadUsage(for: feature)
        let monthKey = Self.currentMonthKey
        if usage.monthKey != monthKey {
            usage = MeteredUsage(count: 0, monthKey: monthKey)
        }
        usage.count += 1
        saveUsage(usage, for: feature)
    }

    /// Returns remaining free uses for this feature. Returns Int.max when no limit applies.
    func remaining(_ feature: MeteredFeature) -> Int {
        guard hasUsageLimits else { return Int.max }
        let used = usageCount(for: feature)
        return max(0, feature.freeLimit - used)
    }

    // MARK: Cloud chat, per conversation

    /// Whether a message in this conversation may go to cloud AI. True for
    /// Pro, on-device AI, a conversation already counted this month, or while
    /// this month's count is below the free limit. Callers ask at the moment
    /// they are about to call a cloud provider.
    func canSendCloudMessage(in conversationID: UUID) -> Bool {
        guard hasUsageLimits else { return true }
        let usage = loadCloudConversationUsage()
        if usage.conversationIDs.contains(conversationID) { return true }
        return usage.usedCount < MeteredFeature.dialectics.freeLimit
    }

    /// Counts this conversation against this month's free cloud chats, once.
    /// No-op when no limit applies or the conversation is already counted.
    func recordCloudMessage(in conversationID: UUID) {
        guard hasUsageLimits else { return }
        var usage = loadCloudConversationUsage()
        guard !usage.conversationIDs.contains(conversationID) else { return }
        usage.conversationIDs.append(conversationID)
        saveCloudConversationUsage(usage)
    }

    private static let cloudConversationsKey = usageKeyPrefix + "dialectics.conversations"

    /// This month's usage. Before the first write it falls back to the old
    /// count-at-creation counter, so uses already made this month still count.
    private func loadCloudConversationUsage() -> CloudConversationUsage {
        let monthKey = Self.currentMonthKey
        if let data = defaults.data(forKey: Self.cloudConversationsKey),
           let usage = try? JSONDecoder().decode(CloudConversationUsage.self, from: data) {
            return usage.monthKey == monthKey
                ? usage
                : CloudConversationUsage(monthKey: monthKey, conversationIDs: [], carriedOverCount: 0)
        }
        let legacy = loadUsage(for: .dialectics)
        return CloudConversationUsage(
            monthKey: monthKey,
            conversationIDs: [],
            carriedOverCount: legacy.monthKey == monthKey ? legacy.count : 0
        )
    }

    private func saveCloudConversationUsage(_ usage: CloudConversationUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: Self.cloudConversationsKey)
    }

    private func usageCount(for feature: MeteredFeature) -> Int {
        if feature == .dialectics {
            return loadCloudConversationUsage().usedCount
        }
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
                source: .trial,
                updatedAt: .now
            )
        )
    }

    func activatePro(renewalDate: Date? = nil, source: SubscriptionSource = .local) {
        updateState(
            EntitlementState(
                tier: .pro,
                isTrialActive: false,
                trialStartedAt: state.trialStartedAt,
                trialEndsAt: state.trialEndsAt,
                renewalDate: renewalDate,
                source: source,
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
