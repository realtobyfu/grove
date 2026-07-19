import SwiftUI

/// iOS Settings screen — List-based with sections for AI, Sync, Appearance,
/// Subscription, and About. Wired into the "More" tab.
struct MobileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(OnboardingService.self) private var onboarding
    @State private var paywallPresentation: PaywallPresentation?
    @State private var syncEnabled = SyncSettings.syncEnabled
    @State private var notificationsEnabled = NudgeSettings.notificationsEnabled

    var body: some View {
        List {
            aiSection
            notificationsSection
            newslettersSection
            syncSection
            appearanceSection
            subscriptionSection
            aboutSection
        }
        .navigationTitle("Settings")
        .onAppear {
            syncEnabled = SyncSettings.syncEnabled
            notificationsEnabled = NudgeSettings.notificationsEnabled
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section("Reminders") {
            Toggle(isOn: $notificationsEnabled) {
                Label("System Notifications", systemImage: "bell")
            }
            .onChange(of: notificationsEnabled) { _, newValue in
                Task {
                    let effectiveValue = await NudgeNotificationService.shared
                        .setNotificationsEnabled(newValue)
                    if notificationsEnabled != effectiveValue {
                        notificationsEnabled = effectiveValue
                    }
                }
            }

            Text("When off, reminders appear only inside Today.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Newsletters

    private var newslettersSection: some View {
        Section("Newsletters") {
            NavigationLink {
                SubscriptionsSettingsView()
            } label: {
                Label("Subscriptions", systemImage: "newspaper")
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
            NavigationLink {
                SyncSettingsView()
                    .navigationTitle("Sync")
            } label: {
                HStack {
                    Label("iCloud Sync", systemImage: "icloud")
                    Spacer()
                    Text(syncStatusLabel)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private var syncStatusLabel: String {
        if entitlement.state.tier == .pro {
            return syncEnabled ? "On" : "Off"
        } else {
            return "Pro"
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
                    if let url = AppConstants.URLs.manageSubscriptions {
                        #if os(iOS)
                        openURL(url)
                        #endif
                    }
                } label: {
                    Label("Manage Subscription", systemImage: "gear")
                }
            } else {
                Button {
                    paywallPresentation = paywallCoordinator.present(
                        feature: nil,
                        source: .proSettings,
                        bypassCooldown: true
                    )
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
                    openURL(url)
                    #endif
                }
            } label: {
                Label("Send Feedback", systemImage: "envelope")
            }

            Button {
                if let url = AppConstants.URLs.privacyPolicy {
                    #if os(iOS)
                    openURL(url)
                    #endif
                }
            } label: {
                Label("Privacy Policy", systemImage: "lock.shield")
            }

            Button {
                if let url = AppConstants.URLs.support {
                    #if os(iOS)
                    openURL(url)
                    #endif
                }
            } label: {
                Label("Support", systemImage: "questionmark.circle")
            }
        }
    }
}
