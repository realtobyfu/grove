import Foundation

/// Where a paywall was presented from. Only sources with a live call site.
enum PaywallSource: String, Codable, Sendable {
    case syncSettings
    case aiSettings
    case chatHistory
    case proSettings
    case dialecticsLimit
}

struct PaywallPresentation: Identifiable {
    let id = UUID()
    let feature: ProFeature?
    let source: PaywallSource
    let pendingAction: (@MainActor () -> Void)?

    init(
        feature: ProFeature?,
        source: PaywallSource,
        pendingAction: (@MainActor () -> Void)? = nil
    ) {
        self.feature = feature
        self.source = source
        self.pendingAction = pendingAction
    }
}

@MainActor
@Observable
final class PaywallCoordinator {
    static let shared = PaywallCoordinator()

    nonisolated private static let cooldownPrefix = "grove.paywall.cooldown."
    nonisolated static let cooldownInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let entitlement: EntitlementService

    init(
        defaults: UserDefaults = .standard,
        entitlement: EntitlementService = .shared
    ) {
        self.defaults = defaults
        self.entitlement = entitlement
    }

    func present(
        feature: ProFeature?,
        source: PaywallSource,
        bypassCooldown: Bool = false,
        pendingAction: (@MainActor () -> Void)? = nil
    ) -> PaywallPresentation? {
        if entitlement.isPro || (feature.map { entitlement.hasAccess(to: $0) } ?? entitlement.isPro) {
            pendingAction?()
            return nil
        }

        if !bypassCooldown && isInCooldown(for: feature) {
            return nil
        }

        return PaywallPresentation(
            feature: feature,
            source: source,
            pendingAction: pendingAction
        )
    }

    func dismiss(_ presentation: PaywallPresentation, converted: Bool) {
        if converted {
            presentation.pendingAction?()
            return
        }

        let key = cooldownKey(for: presentation.feature)
        defaults.set(Date.now, forKey: key)
    }

    func isInCooldown(for feature: ProFeature?, referenceDate: Date = .now) -> Bool {
        let key = cooldownKey(for: feature)
        guard let lastDismissedAt = defaults.object(forKey: key) as? Date else {
            return false
        }
        return referenceDate.timeIntervalSince(lastDismissedAt) < Self.cooldownInterval
    }

    private func cooldownKey(for feature: ProFeature?) -> String {
        let suffix = feature?.rawValue ?? "general"
        return Self.cooldownPrefix + suffix
    }
}
