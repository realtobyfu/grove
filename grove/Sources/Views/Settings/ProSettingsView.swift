#if os(macOS)
import AppKit
#endif
import SwiftUI

struct ProSettingsView: View {
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(StoreKitService.self) private var storeKit
    @Environment(\.openURL) private var openURL
    @State private var paywallPresentation: PaywallPresentation?

    var body: some View {
        Form {
            Section("Plan") {
                HStack {
                    Text("Current plan")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(entitlement.tier.displayName)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                }

                if entitlement.isTrialActive {
                    if let ends = entitlement.trialEndsAt {
                        Text("Trial ends \(ends.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text("Trial is active.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if entitlement.isPro {
                    Text("Pro is active.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)

                    if let renewal = entitlement.state.renewalDate {
                        Text("Renews \(renewal.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if entitlement.state.source == .storeKit {
                        Button("Manage Subscription") {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                #if os(macOS)
                                NSWorkspace.shared.open(url)
                                #else
                                openURL(url)
                                #endif
                            }
                        }
                        .tint(Color.textPrimary)
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("View Pro Plan") {
                        paywallPresentation = paywallCoordinator.present(
                            feature: nil,
                            source: .proSettings,
                            bypassCooldown: true
                        )
                    }
                    .tint(Color.textPrimary)
                    .buttonStyle(.borderedProminent)
                }
            }

#if DEBUG
            Section("Debug") {
                Button("Force Free Tier") {
                    entitlement.downgradeToFree()
                }
                .tint(Color.textPrimary)
                .buttonStyle(.bordered)

                Button("Force Pro Tier") {
                    entitlement.activatePro()
                }
                .tint(Color.textPrimary)
                .buttonStyle(.bordered)

                Button("Start Local Trial (14 days)") {
                    entitlement.startTrial(days: 14)
                }
                .tint(Color.textPrimary)
                .buttonStyle(.bordered)
            }
#endif
        }
        .formStyle(.grouped)
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
    }
}
