import SwiftData
import SwiftUI

/// iOS Settings screen — List-based with sections for AI, Sync, Appearance,
/// Subscription, and About. Wired into the "More" tab.
struct MobileSettingsView: View {
    /// Sheets, as on Today's flashcards row: both views bring their own
    /// dismiss button, which reads wrong on a pushed screen.
    private enum LearningPresentation: String, Identifiable {
        case library, focus
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(OnboardingService.self) private var onboarding
    @State private var paywallPresentation: PaywallPresentation?
    @State private var learningPresentation: LearningPresentation?
    @State private var syncEnabled = SyncSettings.syncEnabled

    var body: some View {
        List {
            // Grouped rows read as cards on the paper page.
            Group {
                aiSection
                newslettersSection
                learningSection
                syncSection
                appearanceSection
                subscriptionSection
                aboutSection
            }
            .listRowBackground(Color.bgCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationTitle("Settings")
        .onAppear {
            syncEnabled = SyncSettings.syncEnabled
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
        .sheet(item: $learningPresentation) { presentation in
            NavigationStack {
                switch presentation {
                case .library: FlashcardLibraryView()
                case .focus: LearningFocusView()
                }
            }
        }
    }

    // MARK: - Newsletters

    private var newslettersSection: some View {
        Section("Following") {
            NavigationLink {
                SubscriptionsSettingsView()
            } label: {
                Label("Subscriptions", systemImage: "newspaper")
            }
        }
    }

    // MARK: - Learning

    /// Always here: Today's flashcards row hides when nothing is due.
    private var learningSection: some View {
        Section("Learning") {
            Button {
                learningPresentation = .library
            } label: {
                Label("Flashcards", systemImage: "rectangle.on.rectangle")
            }

            Button {
                learningPresentation = .focus
            } label: {
                Label("Focus & session length", systemImage: "scope")
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
