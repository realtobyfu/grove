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
            return "\(feature.summary) plus every other Pro capability."
        }
        return "Get unlimited AI workflows, full history, and sync across devices."
    }

    private var paywallFeatures: [ProFeature] {
        if let feature = presentation.feature {
            let remaining = ProFeature.allCases.filter { $0 != feature }
            return [feature] + Array(remaining.prefix(4))
        }
        return Array(ProFeature.allCases.prefix(5))
    }

    private var isPurchasing: Bool {
        if case .purchasing = storeKit.purchaseState {
            return true
        }
        return false
    }

    private var purchaseButtonTitle: String {
        if let intro = storeKit.introOfferDescription {
            return "Start \(intro) - \(storeKit.displayPrice)/year"
        }
        return "Upgrade for \(storeKit.displayPrice)/year"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(titleText)
                        .font(.groveTitleLarge)
                        .foregroundStyle(Color.textPrimary)

                    Text(subtitleText)
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(paywallFeatures) { feature in
                        Label(feature.title, systemImage: "checkmark.circle.fill")
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                    }
                }

                purchaseStateBanner

                VStack(spacing: Spacing.sm) {
                    Button(action: beginPurchase) {
                        HStack(spacing: Spacing.sm) {
                            if isPurchasing {
                                ProgressView()
                                    .tint(Color.textInverse)
                            }
                            Text(isPurchasing ? "Purchasing..." : purchaseButtonTitle)
                                .font(.groveBody)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: LayoutDimensions.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPurchasing)

                    Button("Restore Purchases", action: restorePurchases)
                        .font(.groveBody)
                        .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget)
                        .buttonStyle(.bordered)

                    Button("Not Now") {
                        dismissPaywall(converted: false)
                    }
                    .font(.groveBodySmall)
                    .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget)
                }
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.vertical, LayoutDimensions.sectionSpacing)
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
