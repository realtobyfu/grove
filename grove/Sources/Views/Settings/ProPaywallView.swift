import SwiftUI

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(StoreKitService.self) private var storeKit

    let presentation: PaywallPresentation

    @State private var didDismiss = false

    private var titleText: String {
        if let feature = presentation.feature {
            return "Unlock \(feature.title)"
        }
        return "Upgrade to Grove Pro"
    }

    private var subtitleText: String {
        if let feature = presentation.feature {
            return "\(feature.summary) plus automations, full history, and seamless sync across devices."
        }
        return "Automate recurring work, search your full history, and stay in sync across every device."
    }

    private var overlineText: String {
        if let feature = presentation.feature {
            return "UNLOCK \(feature.title.uppercased())"
        }
        return "GROVE PRO"
    }

    private var paywallFeatures: [ProFeature] {
        if let feature = presentation.feature {
            let remaining = ProFeature.allCases.filter { $0 != feature }
            return [feature] + Array(remaining.prefix(5))
        }
        return Array(ProFeature.allCases.prefix(6))
    }

    private var featuredBenefits: [ProFeature] {
        let defaults: [ProFeature] = [.automations, .sync, .fullHistory]
        let prioritized: [ProFeature]

        if let feature = presentation.feature {
            prioritized = [feature] + defaults.filter { $0 != feature } + paywallFeatures
        } else {
            prioritized = defaults + paywallFeatures
        }

        var seen = Set<String>()
        return prioritized.filter { seen.insert($0.id).inserted }.prefix(3).map(\.self)
    }

    private var additionalBenefits: [ProFeature] {
        let featuredIDs = Set(featuredBenefits.map(\.id))
        return paywallFeatures.filter { !featuredIDs.contains($0.id) }
    }

    private var isPurchasing: Bool {
        if case .purchasing = storeKit.purchaseState {
            return true
        }
        return false
    }

    private var purchaseButtonTitle: String {
        if let intro = storeKit.introOfferDescription {
            return "Start \(intro)"
        }
        return "Upgrade to Pro"
    }

    private var pricingSummary: String {
        if let intro = storeKit.introOfferDescription {
            return "\(intro.capitalized), then \(storeKit.displayPrice) per year."
        }
        return "\(storeKit.displayPrice) billed annually."
    }

    private var purchaseFootnote: String {
        if let intro = storeKit.introOfferDescription {
            return "Try everything for \(intro), then continue for \(storeKit.displayPrice) per year. Cancel anytime in App Store subscriptions."
        }
        return "One yearly subscription for \(storeKit.displayPrice). Cancel anytime in App Store subscriptions."
    }

    private var aiUsageLimitSummary: String {
        "Free includes limited AI each month: 6 Dialectics, 3 reflection prompts, 10 auto-tags, 5 connection suggestions, 1 synthesis, and 3 suggested articles. Pro removes those caps."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    heroHeader

                    Spacer(minLength: Spacing.md)

                    dismissButton
                }

                pricingCallout

                VStack(spacing: Spacing.sm) {
                    Button(action: beginPurchase) {
                        HStack(spacing: Spacing.sm) {
                            if isPurchasing {
                                ProgressView()
                                    .tint(Color.textInverse)
                            }

                            Text(isPurchasing ? "Purchasing..." : purchaseButtonTitle)
                                .font(.groveBodyMedium)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: LayoutDimensions.minTouchTarget)
                    }
                    .buttonStyle(PaywallFilledButtonStyle())
                    .disabled(isPurchasing)

                    Button("Restore Purchases", action: restorePurchases)
                        .font(.groveBodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget)
                        .buttonStyle(.plain)
                }

                purchaseStateBanner

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Top Pro benefits")
                        .sectionHeaderStyle()

                    VStack(spacing: Spacing.sm) {
                        ForEach(featuredBenefits) { feature in
                            featureRow(for: feature)
                        }
                    }
                }

                if !additionalBenefits.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Also included")
                            .sectionHeaderStyle()

                        additionalBenefitsView
                    }
                }

                footerNotes

                Text(purchaseFootnote)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, Spacing.lg)
            .padding(.bottom, LayoutDimensions.sectionSpacing)
        }
        .background(Color.bgPrimary)
        .task {
            await storeKit.loadProduct()
            await storeKit.refreshEntitlementStatus()
            if storeKit.isEntitled {
                dismissPaywall(converted: true)
            }
        }
        .onDisappear {
            guard !didDismiss else { return }
            didDismiss = true
            paywallCoordinator.dismiss(presentation, converted: false)
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.textPrimary)
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.textInverse)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(overlineText)
                        .font(.groveBadge)
                        .tracking(1.0)
                        .foregroundStyle(Color.textSecondary)

                    Text(titleText)
                        .font(.groveTitleLarge)
                        .foregroundStyle(Color.textPrimary)

                    Text(subtitleText)
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dismissButton: some View {
        Button {
            dismissPaywall(converted: false)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .frame(width: LayoutDimensions.minTouchTarget, height: LayoutDimensions.minTouchTarget, alignment: .topTrailing)
        .buttonStyle(.plain)
    }

    private var pricingCallout: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(storeKit.introOfferDescription == nil ? "ANNUAL PLAN" : "START WITH A FREE TRIAL")
                .font(.groveBadge)
                .tracking(1.0)
                .foregroundStyle(Color.textSecondary)

            Text(pricingSummary)
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Cancel anytime", systemImage: "checkmark.shield")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func featureRow(for feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon(for: feature))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textInverse)
                .frame(width: 28, height: 28)
                .background(Color.textPrimary)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(feature.title)
                    .font(.groveBodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Text(feature.summary)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var additionalBenefitsView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(additionalBenefits) { feature in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: icon(for: feature))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 18, height: 18)

                    Text(feature.title)
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Free plan limits")
                .font(.groveBadge)
                .tracking(1.0)
                .foregroundStyle(Color.textTertiary)

            Text(aiUsageLimitSummary)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for feature: ProFeature) -> String {
        switch feature {
        case .automations: return "clock.arrow.circlepath"
        case .batchActions: return "square.stack.3d.up.fill"
        case .savedWorkflows: return "bookmark.fill"
        case .sync: return "arrow.triangle.2.circlepath.icloud"
        case .fullHistory: return "text.magnifyingglass"
        case .smartRouting: return "point.3.connected.trianglepath.dotted"
        case .dialectics: return "bubble.left.and.bubble.right.fill"
        case .reflectionPrompts: return "sparkles.rectangle.stack"
        case .autoTagging: return "tag.fill"
        case .connectionSuggestions: return "point.3.filled.connected.trianglepath.dotted"
        case .synthesis: return "wand.and.stars"
        case .weeklyDigest: return "newspaper.fill"
        case .suggestedArticles: return "doc.text.image.fill"
        }
    }

    @ViewBuilder
    private var purchaseStateBanner: some View {
        switch storeKit.purchaseState {
        case .idle, .purchasing:
            EmptyView()
        case .pending:
            banner(
                text: "Purchase is pending approval. You'll unlock Pro automatically once approved.",
                systemImage: "clock.badge.exclamationmark"
            )
        case .purchased:
            banner(
                text: "Pro unlocked. Applying your access now...",
                systemImage: "checkmark.circle.fill"
            )
        case .failed(let errorMessage):
            banner(
                text: "Purchase failed: \(errorMessage)",
                systemImage: "exclamationmark.triangle.fill"
            )
        }
    }

    private func banner(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.groveBodySmall)
            .foregroundStyle(Color.textSecondary)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    private func beginPurchase() {
        Task { @MainActor in
            await storeKit.purchase()
            if storeKit.isEntitled || isPurchasedState {
                dismissPaywall(converted: true)
            }
        }
    }

    private func restorePurchases() {
        Task { @MainActor in
            await storeKit.restore()
            if storeKit.isEntitled {
                dismissPaywall(converted: true)
            }
        }
    }

    @MainActor
    private func dismissPaywall(converted: Bool) {
        guard !didDismiss else { return }
        didDismiss = true
        paywallCoordinator.dismiss(presentation, converted: converted)
        dismiss()
    }

    private var isPurchasedState: Bool {
        if case .purchased = storeKit.purchaseState {
            return true
        }
        return false
    }
}

private struct PaywallFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var background: Color = .textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.textInverse)
            .padding(.horizontal, Spacing.md)
            .background(isEnabled ? background : Color.textSecondary)
            .clipShape(.rect(cornerRadius: max(LayoutDimensions.cardCornerRadius, 12)))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
