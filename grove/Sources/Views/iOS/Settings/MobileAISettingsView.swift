import SwiftUI

/// AI settings for iOS/iPadOS using the shared LLM runtime policy.
struct MobileAISettingsView: View {
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator

    @State private var isEnabled = LLMServiceConfig.isEnabled
    @State private var providerType = LLMServiceConfig.providerType
    @State private var apiKey = LLMServiceConfig.apiKey
    @State private var model = LLMServiceConfig.model
    @State private var baseURL = LLMServiceConfig.baseURL
    @State private var smartRoutingEnabled = LLMServiceConfig.smartRoutingEnabled
    @State private var showAdvancedProvider = false
    @State private var showAdvancedUsage = false
    @State private var paywallPresentation: PaywallPresentation?
    @State private var refreshID = UUID()
    @State private var budgetEnabled: Bool = TokenTracker.shared.budgetEnabled
    @State private var budgetText: String = {
        let budget = TokenTracker.shared.monthlyBudget
        return "\(budget / 1000)"
    }()

    private var tracker: TokenTracker { TokenTracker.shared }
    private var effectiveProviderType: LLMProviderType { LLMServiceConfig.effectiveProviderType }
    private var isBYOEnabled: Bool { BuildFlags.isBYOEnabled }
    private var monthlyUsageRatio: Double {
        let budget = tracker.monthlyBudget
        guard budget > 0 else { return 0 }
        return Double(tracker.currentMonthTokens) / Double(budget)
    }
    private var showUsageSection: Bool {
        isBYOEnabled || monthlyUsageRatio >= 0.5
    }

    var body: some View {
        List {
            Section("AI Features") {
                Toggle("Enable AI features", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        LLMServiceConfig.isEnabled = newValue
                    }

                statusRow

                Text("Turns off Chat, conversation starters, auto-tagging, and article overviews.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.bgCard)

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
                    HStack(spacing: Spacing.xsm) {
                        Image(systemName: "cloud")
                            .foregroundStyle(Color.textSecondary)
                        Text("Cloud AI is available. Apple Intelligence requires iOS 26 or later.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if providerType == .groq || !LLMServiceConfig.isAppleIntelligenceSupported {
                    if isBYOEnabled {
                        SecureField("Cloud API Key", text: $apiKey)
                            .onChange(of: apiKey) { _, newValue in
                                LLMServiceConfig.apiKey = newValue
                            }
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif

                        if apiKey.isEmpty {
                            Text("Add an API key to enable cloud AI in debug builds.")
                                .font(.groveBadge)
                                .foregroundStyle(Color.textTertiary)
                        }

                        DisclosureGroup("Debug cloud overrides", isExpanded: $showAdvancedProvider) {
                            TextField("Cloud model override", text: $model)
                                .onChange(of: model) { _, newValue in
                                    LLMServiceConfig.model = newValue
                                }
                            Text("Optional debug-only override.")
                                .font(.groveBadge)
                                .foregroundStyle(Color.textTertiary)

                            TextField("Cloud base URL override", text: $baseURL)
                                .onChange(of: baseURL) { _, newValue in
                                    LLMServiceConfig.baseURL = newValue
                                }
                            Text("Optional debug-only override.")
                                .font(.groveBadge)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } else {
                        // Release builds: the cloud model runs on Grove's
                        // hosted service with Grove's own key.
                        Text("Cloud AI is provided by Grove, so there is no API key to set up.")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)

                        if !LLMServiceConfig.isConfigured {
                            Text("Cloud AI isn't available right now.")
                                .font(.groveBadge)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
            .listRowBackground(Color.bgCard)

            Section("Routing") {
                Toggle("Smart cloud fallback", isOn: $smartRoutingEnabled)
                    .disabled(!entitlement.hasAccess(to: .smartRouting))
                    .onChange(of: smartRoutingEnabled) { _, newValue in
                        guard newValue else {
                            LLMServiceConfig.smartRoutingEnabled = false
                            return
                        }
                        LLMServiceConfig.smartRoutingEnabled = true
                    }

                if entitlement.hasAccess(to: .smartRouting) {
                    Text("Prefer on-device intelligence first, then use cloud as fallback when needed.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    HStack(spacing: Spacing.xsm) {
                        Image(systemName: "lock")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                        Text("Smart cloud fallback is available with Pro.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Button("Unlock Pro") {
                        paywallPresentation = paywallCoordinator.present(
                            feature: .smartRouting,
                            source: .aiSettings,
                            pendingAction: {
                                smartRoutingEnabled = true
                                LLMServiceConfig.smartRoutingEnabled = true
                            }
                        )
                    }
                }
            }
            .listRowBackground(Color.bgCard)

            if showUsageSection {
                Section("Usage") {
                    if isBYOEnabled {
                        HStack {
                            Text("Total tokens")
                                .font(.groveBodySecondary)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(formatNumber(tracker.totalTokens))
                                .font(.groveMeta)
                                .foregroundStyle(Color.textPrimary)
                        }

                        HStack {
                            Text("Total AI calls")
                                .font(.groveBodySecondary)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(formatNumber(tracker.callCount))
                                .font(.groveMeta)
                                .foregroundStyle(Color.textPrimary)
                        }

                        if effectiveProviderType == .groq {
                            HStack {
                                Text("Estimated cost")
                                    .font(.groveBodySecondary)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Text(formatCost(tracker.estimatedCost))
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }

                        DisclosureGroup("Advanced usage and limits", isExpanded: $showAdvancedUsage) {
                            usageByService
                                .padding(.top, Spacing.xs)

                            budgetControls
                                .padding(.top, Spacing.sm)

                            Button("Reset Usage") {
                                tracker.resetAll()
                                refreshID = UUID()
                            }
                            .padding(.top, Spacing.xs)
                        }
                    } else {
                        HStack(spacing: Spacing.xsm) {
                            Image(systemName: monthlyUsageRatio >= 1.0 ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                .foregroundStyle(Color.textSecondary)
                            Text("Cloud usage is at \(formatPercent(monthlyUsageRatio)) of this month's limit.")
                                .font(.groveBodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }

                        Text(monthlyUsageRatio >= 1.0 ? "Cloud usage has reached the monthly limit." : "The limit resets at the start of each month.")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.bgCard)
            }

        }
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationTitle("AI Settings")
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .id(refreshID)
        .onAppear {
            smartRoutingEnabled = LLMServiceConfig.smartRoutingEnabled
        }
        .onChange(of: entitlement.state.updatedAt) {
            smartRoutingEnabled = LLMServiceConfig.smartRoutingEnabled
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: Spacing.xsm) {
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
            if isBYOEnabled {
                return "Add a cloud API key to enable AI."
            }
            return "Cloud AI isn't available right now."
        }
        return "Apple Intelligence is unavailable on this device."
    }

    // MARK: - Apple Intelligence Status

    private var appleIntelligenceStatus: some View {
        Group {
            if #available(macOS 26, iOS 26, *), AppleIntelligenceProvider.isAvailable {
                HStack(spacing: Spacing.xsm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.textPrimary)
                    Text("Apple Intelligence is available on this device.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                HStack(spacing: Spacing.xsm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.textSecondary)
                    Text("Apple Intelligence is not available. Check that it is enabled in Settings.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text("On-device inference with no API key required.")
                .font(.groveBadge)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Usage

    private var usageByService: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
                        Text(service.displayName)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatNumber(service.totalTokens) + " tokens")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textPrimary)
                            if effectiveProviderType == .groq {
                                Text(formatCost(service.estimatedCost))
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
                        .frame(width: 80)
                        .font(.groveMeta)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: budgetText) { _, newValue in
                            if let value = Int(newValue), value > 0 {
                                tracker.monthlyBudget = value * 1000
                            }
                        }
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text("K")
                        .font(.groveMeta)
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
                    HStack(spacing: Spacing.xsm) {
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

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatCost(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(4)))
    }

    private func formatPercent(_ ratio: Double) -> String {
        let clamped = max(0, ratio)
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }
}
