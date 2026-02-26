import SwiftUI

// MARK: - Onboarding Button Style

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodyMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(isEnabled ? Color.textPrimary : Color.textSecondary)
            .clipShape(.rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Onboarding Page

private enum OnboardingPage: Int, CaseIterable {
    case welcome
    case capture
    case organize
    case goals
    case ready
}

// MARK: - Flow View

struct OnboardingFlowView: View {
    @Environment(OnboardingService.self) private var onboarding

    @State private var page: OnboardingPage = .welcome
    @State private var selectedCapture: Set<CaptureType> = []
    @State private var selectedOrganize: OrganizeStyle? = nil
    @State private var selectedGoals: Set<OnboardingGoal> = []
    @State private var navigatingForward = true
    @State private var iconAppeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation row
                HStack {
                    if page != .welcome {
                        Button {
                            navigatingForward = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                goBack()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.groveBody)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, Spacing.md)
                .padding(.horizontal, Spacing.lg)

                // Page content
                Group {
                    switch page {
                    case .welcome:
                        welcomePage
                    case .capture:
                        capturePage
                    case .organize:
                        organizePage
                    case .goals:
                        goalsPage
                    case .ready:
                        readyPage
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
                ))

                // Page indicator dots
                pageIndicator
                    .padding(.bottom, Spacing.md)
            }
            .frame(maxWidth: 460)
            .background(Color.bgPrimary)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }

    // MARK: - Navigation

    private func goForward() {
        guard let idx = OnboardingPage.allCases.firstIndex(of: page),
              idx < OnboardingPage.allCases.count - 1 else { return }
        page = OnboardingPage.allCases[idx + 1]
    }

    private func goBack() {
        guard let idx = OnboardingPage.allCases.firstIndex(of: page),
              idx > 0 else { return }
        page = OnboardingPage.allCases[idx - 1]
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(OnboardingPage.allCases, id: \.rawValue) { p in
                Circle()
                    .fill(p == page ? Color.textPrimary : Color.borderPrimary)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: Spacing.lg) {
            // App icon
            Group {
                if let nsImage = NSApplication.shared.applicationIconImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "leaf")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(.rect(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
                .scaleEffect(iconAppeared ? 1.0 : 0.8)
                .opacity(iconAppeared ? 1.0 : 0.0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.35)) {
                        iconAppeared = true
                    }
                }

            // Title
            Text("Grove")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)

            // Tagline
            Text("Capture, organize, and reflect.")
                .font(.groveGhostText)
                .foregroundStyle(Color.textSecondary)

            Divider()
                .padding(.horizontal, Spacing.lg)

            // How it works section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("HOW IT WORKS")
                    .sectionHeaderStyle()

                featureRow(
                    icon: "link",
                    description: "Save links, notes, and ideas from anywhere"
                )
                featureRow(
                    icon: "square.grid.2x2",
                    description: "Group items into boards by topic or project"
                )
                featureRow(
                    icon: "bubble.left.and.bubble.right",
                    description: "Chat with Grove to explore your thinking"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
    }

    // MARK: - Page 2: Capture

    private var capturePage: some View {
        VStack(spacing: Spacing.lg) {
            Text("What do you capture?")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)

            Text("Pick any that apply.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            FlowLayout(spacing: Spacing.sm) {
                ForEach(CaptureType.allCases) { item in
                    chipButton(item, selected: selectedCapture.contains(item)) {
                        if selectedCapture.contains(item) {
                            selectedCapture.remove(item)
                        } else {
                            selectedCapture.insert(item)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
    }

    // MARK: - Page 3: Organize

    private var organizePage: some View {
        VStack(spacing: Spacing.lg) {
            Text("How do you organize?")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)

            Text("Pick one.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            FlowLayout(spacing: Spacing.sm) {
                ForEach(OrganizeStyle.allCases) { item in
                    chipButton(item, selected: selectedOrganize == item) {
                        selectedOrganize = item
                    }
                }
            }
            .padding(.vertical, Spacing.sm)

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
    }

    // MARK: - Page 4: Goals

    private var goalsPage: some View {
        VStack(spacing: Spacing.lg) {
            Text("What are you here to do?")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)

            Text("Pick any that apply.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            FlowLayout(spacing: Spacing.sm) {
                ForEach(OnboardingGoal.allCases) { item in
                    chipButton(item, selected: selectedGoals.contains(item)) {
                        if selectedGoals.contains(item) {
                            selectedGoals.remove(item)
                        } else {
                            selectedGoals.insert(item)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
    }

    // MARK: - Page 5: Ready

    private var readyPage: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.textSecondary)

            Text("You're all set")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)

            // Summary of selections
            if !selectedCapture.isEmpty || selectedOrganize != nil || !selectedGoals.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if !selectedCapture.isEmpty {
                        readonlyChipGroup(
                            items: selectedCapture.sorted(by: { $0.rawValue < $1.rawValue }).map(\.label)
                        )
                    }
                    if let style = selectedOrganize {
                        readonlyChipGroup(items: [style.label])
                    }
                    if !selectedGoals.isEmpty {
                        readonlyChipGroup(
                            items: selectedGoals.sorted(by: { $0.rawValue < $1.rawValue }).map(\.label)
                        )
                    }
                }
            }

            Text("We'll walk you through the basics next.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)

            Button("Get Started") {
                OnboardingPreferences.captureTypes = selectedCapture
                OnboardingPreferences.organizeStyle = selectedOrganize
                OnboardingPreferences.goals = selectedGoals
                OnboardingPreferences.selectedUseCases = derivedUseCases()
                onboarding.complete()
                CoachMarkService.shared.startGuide()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
    }

    // MARK: - Shared Components

    private func continueButton(action: @escaping () -> Void) -> some View {
        Button("Continue", action: action)
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
    }

    private func featureRow(icon: String, description: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, alignment: .center)

            Text(description)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)

            Spacer()
        }
    }

    private func chipButton<T: RawRepresentable & Identifiable>(_ item: T, selected: Bool, action: @escaping () -> Void) -> some View where T: Hashable {
        let label: String = {
            if let c = item as? CaptureType { return c.label }
            if let o = item as? OrganizeStyle { return o.label }
            if let g = item as? OnboardingGoal { return g.label }
            return ""
        }()
        return Button(action: action) {
            Text(label)
                .font(.groveBodySmall)
                .foregroundStyle(selected ? Color.textInverse : Color.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(selected ? Color.textPrimary : Color.bgCard)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.clear : Color.borderPrimary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    private func readonlyChipGroup(items: [String]) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(items, id: \.self) { label in
                Text(label)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.bgCard)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
    }

    // MARK: - Legacy Use Case Mapping

    private func derivedUseCases() -> Set<GroveUseCase> {
        var result = Set<GroveUseCase>()
        if selectedCapture.contains(.links) { result.insert(.reading) }
        if selectedCapture.contains(.notes) { result.insert(.notes) }
        if selectedCapture.contains(.courses) { result.insert(.learning) }
        if selectedGoals.contains(.research) { result.insert(.reading) }
        if selectedGoals.contains(.journaling) { result.insert(.journaling) }
        if selectedOrganize == .byProject { result.insert(.projects) }
        return result
    }
}
