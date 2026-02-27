import SwiftUI

/// AI provider configuration for iOS — provider picker, API key, model selection,
/// token usage display from TokenTracker.
struct MobileAISettingsView: View {
    @AppStorage("grove.ai.enabled") private var isEnabled = true
    @AppStorage("grove.ai.providerType") private var providerType = "appleIntelligence"
    @AppStorage("grove.ai.apiKey") private var apiKey = ""
    @AppStorage("grove.ai.model") private var model = "llama-3.3-70b-versatile"
    @Environment(EntitlementService.self) private var entitlement
    @State private var tracker = TokenTracker.shared

    private var isCloudProvider: Bool {
        providerType == "cloud"
    }

    var body: some View {
        List {
            aiToggleSection
            providerSection
            if isCloudProvider {
                cloudConfigSection
            }
            usageSection
        }
        .navigationTitle("AI Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - AI Toggle

    private var aiToggleSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Features")
                        .font(.groveBody)
                    Text(isEnabled ? "Active" : "Disabled")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        } footer: {
            Text("AI powers auto-tagging, connection suggestions, conversation starters, and Dialectics chat.")
        }
    }

    // MARK: - Provider Selection

    private var providerSection: some View {
        Section {
            Picker("Provider", selection: $providerType) {
                Text("Apple Intelligence").tag("appleIntelligence")
                Text("Cloud (Groq)").tag("cloud")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Provider")
        } footer: {
            if isCloudProvider {
                Text("Groq provides fast cloud inference. Requires an API key.")
            } else {
                Text("Uses on-device Apple Intelligence when available.")
            }
        }
    }

    // MARK: - Cloud Config

    private var cloudConfigSection: some View {
        Section("Cloud Configuration") {
            HStack {
                Text("API Key")
                    .font(.groveBody)
                Spacer()
                SecureField("Enter API key", text: $apiKey)
                    .font(.groveMeta)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }

            Picker("Model", selection: $model) {
                Text("Llama 3.3 70B").tag("llama-3.3-70b-versatile")
                Text("Llama 3.1 8B").tag("llama-3.1-8b-instant")
                Text("Mixtral 8x7B").tag("mixtral-8x7b-32768")
            }
        }
    }

    // MARK: - Usage

    private var usageSection: some View {
        Section("Usage This Month") {
            HStack {
                Text("Total Tokens")
                Spacer()
                Text(formatTokens(tracker.currentMonthTokens))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack {
                Text("AI Calls")
                Spacer()
                Text("\(tracker.callCount)")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack {
                Text("Estimated Cost")
                Spacer()
                Text(String(format: "$%.2f", tracker.estimatedCost))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            if !tracker.usageByService.isEmpty {
                DisclosureGroup("Usage by Service") {
                    ForEach(tracker.usageByService) { usage in
                        HStack {
                            Text(usage.service.capitalized)
                                .font(.groveBodySecondary)
                            Spacer()
                            Text(formatTokens(usage.totalTokens))
                                .font(.groveMeta)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            }

            // Budget controls
            Toggle("Monthly Budget", isOn: Binding(
                get: { tracker.budgetEnabled },
                set: { tracker.budgetEnabled = $0 }
            ))

            if tracker.budgetEnabled {
                HStack {
                    Text("Limit")
                    Spacer()
                    Text("\(tracker.monthlyBudget / 1000)K tokens")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
