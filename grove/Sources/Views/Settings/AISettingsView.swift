import SwiftUI

/// Settings view for configuring LLM (AI) features.
/// Keeps core setup visible and tucks diagnostics behind advanced disclosure groups.
struct AISettingsView: View {
    @State private var isEnabled = LLMServiceConfig.isEnabled
    @State private var providerType = LLMServiceConfig.providerType
    @State private var apiKey = LLMServiceConfig.apiKey
    @State private var model = LLMServiceConfig.model
    @State private var baseURL = LLMServiceConfig.baseURL
    @State private var showAdvancedProvider = false
    @State private var showAdvancedUsage = false
    @State private var refreshID = UUID()
    @State private var budgetEnabled: Bool = TokenTracker.shared.budgetEnabled
    @State private var budgetText: String = {
        let budget = TokenTracker.shared.monthlyBudget
        return "\(budget / 1000)"
    }()

    private var tracker: TokenTracker { TokenTracker.shared }
    private var effectiveProviderType: LLMProviderType { LLMServiceConfig.effectiveProviderType }

    var body: some View {
        Form {
            Section("AI Features") {
                Toggle("Enable AI features", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        LLMServiceConfig.isEnabled = newValue
                    }

                statusRow

                Text("Disables AI-powered tagging, suggestions, nudges, and synthesis.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Provider") {
                if LLMServiceConfig.isAppleIntelligenceSupported {
                    Picker("AI Provider", selection: $providerType) {
                        ForEach(LLMProviderType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: providerType) { _, newValue in
                        LLMServiceConfig.providerType = newValue
                        refreshID = UUID()
                    }

                    if providerType == .appleIntelligence {
                        appleIntelligenceStatus
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud")
                            .foregroundStyle(Color.textSecondary)
                        Text("Using Groq cloud API. Apple Intelligence requires macOS 26 or later.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if providerType == .groq || !LLMServiceConfig.isAppleIntelligenceSupported {
                    SecureField("Groq API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            LLMServiceConfig.apiKey = newValue
                        }

                    if apiKey.isEmpty {
                        Text("Add an API key to enable cloud AI.")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                    }

                    DisclosureGroup("Advanced provider options", isExpanded: $showAdvancedProvider) {
                        TextField("Model", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model) { _, newValue in
                                LLMServiceConfig.model = newValue
                            }
                        Text("Default: moonshotai/kimi-k2-instruct")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)

                        TextField("Base URL", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: baseURL) { _, newValue in
                                LLMServiceConfig.baseURL = newValue
                            }
                        Text("Default: https://api.groq.com/openai/v1/chat/completions")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Section("Usage") {
                HStack {
                    Text("Total tokens")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(formatNumber(tracker.totalTokens))
                        .font(.custom("IBMPlexMono-SemiBold", size: 13))
                        .foregroundStyle(Color.textPrimary)
                }

                HStack {
                    Text("Total AI calls")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(formatNumber(tracker.callCount))
                        .font(.custom("IBMPlexMono-SemiBold", size: 13))
                        .foregroundStyle(Color.textPrimary)
                }

                if effectiveProviderType == .groq {
                    HStack {
                        Text("Estimated cost")
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(formatCost(tracker.estimatedCost))
                            .font(.custom("IBMPlexMono-SemiBold", size: 13))
                            .foregroundStyle(Color.textPrimary)
                    }
                }

                DisclosureGroup("Advanced usage and limits", isExpanded: $showAdvancedUsage) {
                    usageByService
                        .padding(.top, 4)

                    budgetControls
                        .padding(.top, 8)

                    Button("Reset Usage") {
                        tracker.resetAll()
                        refreshID = UUID()
                    }
                    .padding(.top, 4)
                }
            }

            Section("Synthesis") {
                if LLMServiceConfig.isConfigured {
                    Text("Uses AI to generate themes, wiki-links, and reflection highlights.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Uses local keyword extraction until AI is configured.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }

                Text("Available from the board header toolbar and tag cluster headers.")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
        .id(refreshID)
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: LLMServiceConfig.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .foregroundStyle(LLMServiceConfig.isConfigured ? Color.textPrimary : Color.textSecondary)
            Text(statusText)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var statusText: String {
        if !isEnabled {
            return "AI features are off."
        }
        if LLMServiceConfig.isConfigured {
            return "Ready with \(effectiveProviderType.displayName)."
        }
        if effectiveProviderType == .groq {
            return "Add a Groq API key to enable AI."
        }
        return "Apple Intelligence is unavailable on this Mac."
    }

    // MARK: - Apple Intelligence Status

    private var appleIntelligenceStatus: some View {
        Group {
            if AppleIntelligenceProvider.isAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.textPrimary)
                    Text("Apple Intelligence is available on this Mac.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.textSecondary)
                    Text("Apple Intelligence is not available. Check that it is enabled in System Settings.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text("On-device inference with no API key required.")
                .font(.groveBadge)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Advanced Usage

    private var usageByService: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage by Service")
                .font(.groveBadge)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)

            let services = tracker.usageByService
            if services.isEmpty {
                Text("No usage recorded yet.")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(services) { service in
                    HStack {
                        Text(displayName(for: service.service))
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatNumber(service.totalTokens) + " tokens")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textPrimary)
                            if effectiveProviderType == .groq {
                                Text(formatCost(Double(service.totalTokens) / 1_000_000.0 * 1.50))
                                    .font(.groveBadge)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var budgetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable monthly budget limit", isOn: $budgetEnabled)
                .onChange(of: budgetEnabled) { _, newValue in
                    tracker.budgetEnabled = newValue
                }

            if budgetEnabled {
                HStack {
                    Text("Budget (thousands of tokens)")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    TextField("1000", text: $budgetText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.groveShortcut)
                        .onChange(of: budgetText) { _, newValue in
                            if let value = Int(newValue), value > 0 {
                                tracker.monthlyBudget = value * 1000
                            }
                        }
                    Text("K")
                        .font(.groveShortcut)
                        .foregroundStyle(Color.textSecondary)
                }

                HStack {
                    Text("Used this month")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(formatNumber(tracker.currentMonthTokens) + " / " + formatNumber(tracker.monthlyBudget))
                        .font(.groveMeta)
                        .foregroundStyle(Color.textPrimary)
                }

                if tracker.isBudgetExceeded {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.textPrimary)
                        Text("Budget exceeded. AI features pause until next month or a higher budget.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            Text("When the limit is reached, new AI calls are paused automatically.")
                .font(.groveBadge)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.4f", cost)
    }

    private func displayName(for service: String) -> String {
        switch service {
        case "tagging": return "Auto-Tagging"
        case "suggestions": return "Connection Suggestions"
        case "reflection_prompts": return "Reflection Prompts"
        case "nudges": return "Smart Nudges"
        case "synthesis": return "Synthesis"
        case "digest": return "Weekly Digest"
        case "learning_path": return "Learning Paths"
        case "overview": return "Article Overview"
        case "dialectics": return "Dialectics"
        default: return service.capitalized
        }
    }
}
