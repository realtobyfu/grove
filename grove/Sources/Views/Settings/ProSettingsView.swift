#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct ProSettingsView: View {
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(StoreKitService.self) private var storeKit
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
                                UIApplication.shared.open(url)
                                #endif
                            }
                        }
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
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Restore") {
                Button("Restore Purchases") {
                    Task { await storeKit.restore() }
                }
                .buttonStyle(.bordered)
            }

            Section("Included in Pro") {
                ForEach(ProFeature.allCases) { feature in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                        Text(feature.summary)
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }

#if DEBUG
            Section("Debug") {
                Button("Force Free Tier") {
                    entitlement.downgradeToFree()
                }
                .buttonStyle(.bordered)

                Button("Force Pro Tier") {
                    entitlement.activatePro()
                }
                .buttonStyle(.bordered)

                Button("Start Local Trial (14 days)") {
                    entitlement.startTrial(days: 14)
                }
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
