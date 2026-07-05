import SwiftUI

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(StoreKitService.self) private var storeKit

    let presentation: PaywallPresentation

    @State private var didDismiss = false

    private static let defaultHeroFeatures: [ProFeature] = [.automations, .sync, .fullHistory, .dialectics]

    private var heroFeatures: [ProFeature] {
        var features = Self.defaultHeroFeatures
        if let feature = presentation.feature {
            features.removeAll { $0 == feature }
            features.insert(feature, at: 0)
        }
        return Array(features.prefix(4))
    }

    private var remainingFeaturesLine: String {
        let shown = Set(heroFeatures)
        let remaining = ProFeature.allCases.filter { !shown.contains($0) }
        let names = remaining.prefix(3).map { $0.title.lowercased() }
        guard !names.isEmpty else { return "" }
        return "Plus \(names.joined(separator: ", ")), and everything else in Pro."
    }

    private var overlineText: String {
        if let feature = presentation.feature {
            return "UNLOCK \(feature.title.uppercased())"
        }
        return "GROVE PRO"
    }

    private var titleText: String {
        if let feature = presentation.feature {
            return "Get \(feature.title) and more"
        }
        return "Make Grove your daily system"
    }

    private var subtitleText: String {
        if let feature = presentation.feature {
            return "\(feature.summary) Included with everything else in Pro."
        }
        return "Automate busywork, search your full history, and stay in sync on every device."
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

    private var pricingText: String {
        if let intro = storeKit.introOfferDescription {
            return "\(intro.capitalized), then \(storeKit.displayPrice) per year"
        }
        if let monthlyPrice = storeKit.monthlyDisplayPrice {
            return "\(storeKit.displayPrice) per year — about \(monthlyPrice) per month"
        }
        return "\(storeKit.displayPrice) per year"
    }

    private var renewalFootnote: String {
        "Grove Pro Annual is a 1-year subscription that renews automatically unless canceled in App Store subscriptions."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                featureList
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseFooter
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
#if os(macOS)
        .frame(width: 440, height: 600)
#endif
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    // MARK: - Header

    private var header: some View {
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
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitleText)
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .keyboardShortcut(.cancelAction)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(heroFeatures) { feature in
                featureRow(for: feature)
            }

            if !remainingFeaturesLine.isEmpty {
                Text(remainingFeaturesLine)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func featureRow(for feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon(for: feature))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 24, height: 24)

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

    // MARK: - Purchase Footer

    private var purchaseFooter: some View {
        VStack(spacing: Spacing.sm) {
            purchaseStateBanner

            Text(pricingText)
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

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

            Text(renewalFootnote)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            secondaryActions
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 1)
        }
    }

    private var secondaryActions: some View {
        ViewThatFits {
            HStack(spacing: Spacing.sm) {
                restoreButton

                separatorDot

                legalLink("Privacy Policy", url: AppConstants.URLs.privacyPolicy)

                separatorDot

                legalLink("Terms of Use", url: AppConstants.URLs.termsOfUse)
            }

            VStack(spacing: Spacing.xs) {
                restoreButton
                legalLink("Privacy Policy", url: AppConstants.URLs.privacyPolicy)
                legalLink("Terms of Use", url: AppConstants.URLs.termsOfUse)
            }
        }
        .font(.groveBodySmall)
    }

    private var restoreButton: some View {
        Button("Restore Purchases", action: restorePurchases)
            .foregroundStyle(Color.textSecondary)
            .buttonStyle(.plain)
    }

    private var separatorDot: some View {
        Text("•")
            .foregroundStyle(Color.textTertiary)
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

    // MARK: - Actions

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
