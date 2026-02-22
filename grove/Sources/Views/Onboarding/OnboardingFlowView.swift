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
    case useCases
    case featureTour
    case ready
}

// MARK: - Flow View

struct OnboardingFlowView: View {
    @Environment(OnboardingService.self) private var onboarding

    @State private var page: OnboardingPage = .welcome
    @State private var selectedUseCases: Set<GroveUseCase> = []
    @State private var navigatingForward = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation row: back button only (no X)
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
                .padding(.top, Spacing.lg)
                .padding(.horizontal, Spacing.lg)

                // Page content
                Group {
                    switch page {
                    case .welcome:
                        welcomePage
                    case .useCases:
                        useCasesPage
                    case .featureTour:
                        featureTourPage
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
                    .padding(.bottom, Spacing.lg)
            }
            .frame(maxWidth: 680)
            .background(Color.bgPrimary)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
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
            Spacer()

            // App icon
            Image("AppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )

            // Title
            Text("Grove")
                .font(.groveTitle)
                .foregroundStyle(Color.textPrimary)

            // Tagline
            Text("Capture, organize, and reflect.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)

            // Description
            Text("Save links and notes, organize them into boards, and use AI-powered conversations to explore your thinking.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer()

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xxl)
        .frame(minHeight: 420)
    }

    // MARK: - Page 2: Use Cases

    private var useCasesPage: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Header
            Text("What brings you to Grove?")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            // Subtitle
            Text("Pick as many as you'd like.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            // Chip grid
            chipGrid
                .padding(.vertical, Spacing.sm)

            Spacer()

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xxl)
        .frame(minHeight: 420)
    }

    // MARK: - Page 3: Feature Tour

    private var featureTourPage: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Text("Here's how Grove works")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: Spacing.lg) {
                featureRow(
                    icon: "link",
                    title: "Capture",
                    description: "Save links, notes, and ideas from anywhere."
                )
                featureRow(
                    icon: "square.grid.2x2",
                    title: "Organize",
                    description: "Group items into boards by topic or project."
                )
                featureRow(
                    icon: "bubble.left.and.bubble.right",
                    title: "Reflect",
                    description: "Chat with Grove to explore your thinking."
                )
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()

            continueButton {
                navigatingForward = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    goForward()
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xxl)
        .frame(minHeight: 420)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.groveBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Page 4: Ready

    private var readyPage: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)

            Text("You're all set")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            // Show selected use cases as readonly chips
            if !selectedUseCases.isEmpty {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(Array(selectedUseCases).sorted(by: { $0.rawValue < $1.rawValue })) { useCase in
                        Text(useCase.label)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.bgCard)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }
            }

            Text("We'll walk you through the basics next.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)

            Spacer()

            Button("Get Started") {
                OnboardingPreferences.selectedUseCases = selectedUseCases
                onboarding.complete()
                CoachMarkService.shared.startGuide()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xxl)
        .frame(minHeight: 420)
    }

    // MARK: - Shared Continue Button

    private func continueButton(action: @escaping () -> Void) -> some View {
        Button("Continue", action: action)
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
    }

    // MARK: - Chip Grid

    private var chipGrid: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(GroveUseCase.allCases) { useCase in
                useCaseChip(useCase)
            }
        }
    }

    private func useCaseChip(_ useCase: GroveUseCase) -> some View {
        let isSelected = selectedUseCases.contains(useCase)
        return Button {
            if isSelected {
                selectedUseCases.remove(useCase)
            } else {
                selectedUseCases.insert(useCase)
            }
        } label: {
            Text(useCase.label)
                .font(.groveBodySmall)
                .foregroundStyle(isSelected ? Color.textInverse : Color.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.textPrimary : Color.bgCard)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.clear : Color.borderPrimary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
