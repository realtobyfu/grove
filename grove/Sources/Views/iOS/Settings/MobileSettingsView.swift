import SwiftUI

/// iOS Settings screen — List-based with sections for AI, Sync, Appearance,
/// Subscription, and About. Wired into the "More" tab.
struct MobileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var entitlement = EntitlementService.shared
    @State private var onboarding = OnboardingService.shared
    @State private var showPaywall = false

    var body: some View {
        List {
            aiSection
            syncSection
            appearanceSection
            subscriptionSection
            aboutSection
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                ProPaywallView(presentation: PaywallPresentation(feature: nil, source: .proSettings))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showPaywall = false }
                        }
                    }
            }
        }
    }

    // MARK: - AI Provider

    private var aiSection: some View {
        Section("Intelligence") {
            NavigationLink {
                MobileAISettingsView()
            } label: {
                Label("AI Settings", systemImage: "brain")
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("Sync") {
            HStack {
                Label("iCloud Sync", systemImage: "icloud")
                Spacer()
                if entitlement.state.tier == .pro {
                    Text("Enabled")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Button("Unlock Pro") {
                        showPaywall = true
                    }
                    .font(.groveMeta)
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle(isOn: Binding(
                get: { AppearanceSettings.monochromeCoverImages },
                set: { AppearanceSettings.monochromeCoverImages = $0 }
            )) {
                Label("Monochrome Images", systemImage: "circle.lefthalf.filled")
            }

            Button {
                onboarding.presentReplay()
            } label: {
                Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Label("Current Plan", systemImage: "crown")
                Spacer()
                Text(entitlement.state.tier == .pro ? "Pro" : "Free")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }

            if entitlement.state.tier == .pro {
                if let renewalDate = entitlement.state.renewalDate {
                    HStack {
                        Text("Renews")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(renewalDate, style: .date)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    }
                } label: {
                    Label("Manage Subscription", systemImage: "gear")
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to Pro", systemImage: "star")
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            Button {
                if let url = URL(string: "mailto:3tobiasfu@gmail.com?subject=Grove%20Feedback") {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Label("Send Feedback", systemImage: "envelope")
            }

            Button {
                if let url = URL(string: "https://grove.dev/privacy") {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Label("Privacy Policy", systemImage: "lock.shield")
            }
        }
    }
}
