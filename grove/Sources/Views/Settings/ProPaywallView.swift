import SwiftUI

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(StoreKitService.self) private var storeKit

    let presentation: PaywallPresentation

    @State private var didDismiss = false
    @State private var isShowingAllFeatures = false

    private var titleText: String {
        if let feature = presentation.feature {
            return "Get \(feature.title) and more"
        }
        return "Make Grove your daily system"
    }

    private var subtitleText: String {
        if let feature = presentation.feature {
            return "\(feature.summary) Get the full Pro toolkit with automations, instant history search, and seamless sync across every device."
        }
        return "Turn Grove into your execution system: automate recurring busywork, find anything from your history in seconds, and keep momentum on every device."
    }

    private var overlineText: String {
        if let feature = presentation.feature {
            return "UNLOCK \(feature.title.uppercased())"
        }
        return "GROVE PRO"
    }

    private var everythingInProFeatures: [ProFeature] {
        let defaults: [ProFeature] = [.automations, .sync, .fullHistory]
        let prioritized: [ProFeature]

        if let feature = presentation.feature {
            prioritized = [feature] + defaults.filter { $0 != feature } + ProFeature.allCases
        } else {
            prioritized = defaults + ProFeature.allCases
        }

        var seen = Set<String>()
        return prioritized.filter { seen.insert($0.id).inserted }
    }

    private var essentialFeatures: [ProFeature] {
        let essentials: [ProFeature] = [.automations, .sync, .fullHistory, .dialectics, .autoTagging, .smartRouting]
        let prioritized: [ProFeature]

        if let feature = presentation.feature {
            prioritized = [feature] + essentials.filter { $0 != feature }
        } else {
            prioritized = essentials
        }

        var seen = Set<String>()
        return prioritized.filter { seen.insert($0.id).inserted }.prefix(6).map(\.self)
    }

    private var additionalFeatures: [ProFeature] {
        let essentialIDs = Set(essentialFeatures.map(\.id))
        return everythingInProFeatures.filter { !essentialIDs.contains($0.id) }
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
            if let monthlyPrice = storeKit.monthlyDisplayPrice {
                return "\(intro.capitalized), then \(monthlyPrice) per month billed annually at \(storeKit.displayPrice)."
            }
            return "\(intro.capitalized), then \(storeKit.displayPrice) per year."
        }
        if let monthlyPrice = storeKit.monthlyDisplayPrice {
            return "\(monthlyPrice) per month, billed annually at \(storeKit.displayPrice)."
        }
        return "\(storeKit.displayPrice) billed annually."
    }

    private var purchaseFootnote: String {
        if let intro = storeKit.introOfferDescription {
            return "Full access during your \(intro). After that, the subscription renews annually unless canceled in App Store subscriptions."
        }
        return "One yearly subscription that renews automatically unless canceled in App Store subscriptions."
    }

    private var aiUsageSummary: String {
        "Free includes monthly AI limits. Pro unlocks unlimited AI tools, automations, full-history search, and sync."
    }

    private var aiUsageLimitFootnote: String {
        "Free monthly caps: 6 Dialectics, 3 reflection prompts, 10 auto-tags, 5 connection suggestions, 1 synthesis, and 3 suggested articles."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                heroHeader

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

                    Text(pricingSummary)
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(purchaseFootnote)
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    subscriptionDisclosureCard

                    legalLinks
                }

                purchaseStateBanner

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Everything in Pro")
                        .sectionHeaderStyle()

                    Text("All features below are included in a single Pro plan.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: Spacing.sm) {
                        ForEach(essentialFeatures) { feature in
                            featureRow(for: feature)
                        }
                    }

                    if !additionalFeatures.isEmpty {
                        DisclosureGroup(isExpanded: $isShowingAllFeatures) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(additionalFeatures) { feature in
                                    collapsedFeatureRow(for: feature)
                                }
                            }
                            .padding(.top, Spacing.sm)
                        } label: {
                            Text("Show \(additionalFeatures.count) more features")
                                .font(.groveBodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }
                }

                footerNotes

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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.textPrimary)
                        .frame(width: 30, height: 30)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textInverse)
                }

                Text(overlineText)
                    .font(.groveBadge)
                    .tracking(1.0)
                    .foregroundStyle(Color.textSecondary)

                Spacer(minLength: Spacing.sm)

                dismissButton
            }

            Text(titleText)
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)

            valuePropositionCard
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

    private func collapsedFeatureRow(for feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon(for: feature))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 16, height: 16)

            Text(feature.title)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            Spacer(minLength: 0)
        }
    }

    private var valuePropositionCard: some View {
        Text(subtitleText)
            .font(.groveBody)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    private var subscriptionDisclosureCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Subscription details")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            Text("Grove Pro Annual")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textPrimary)

            Text("Length: 1 year")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            Text("Price: \(storeKit.displayPrice) per year")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            if let monthlyPrice = storeKit.monthlyDisplayPrice {
                Text("Equivalent: \(monthlyPrice) per month, billed annually")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .cardStyle()
    }

    private var legalLinks: some View {
        ViewThatFits {
            HStack(spacing: Spacing.sm) {
                legalLink("Privacy Policy", url: AppConstants.URLs.privacyPolicy)

                Text("•")
                    .foregroundStyle(Color.textTertiary)

                legalLink("Terms of Use", url: AppConstants.URLs.termsOfUse)

                Text("•")
                    .foregroundStyle(Color.textTertiary)

                legalLink("Support", url: AppConstants.URLs.support)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: Spacing.xs) {
                legalLink("Privacy Policy", url: AppConstants.URLs.privacyPolicy)
                legalLink("Terms of Use", url: AppConstants.URLs.termsOfUse)
                legalLink("Support", url: AppConstants.URLs.support)
            }
            .frame(maxWidth: .infinity)
        }
        .font(.groveBodySmall)
    }

    @ViewBuilder
    private func legalLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
                .foregroundStyle(Color.textSecondary)
        } else {
            Text(title)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Why upgrade")
                .font(.groveBadge)
                .tracking(1.0)
                .foregroundStyle(Color.textTertiary)

            Text(aiUsageSummary)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(aiUsageLimitFootnote)
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
