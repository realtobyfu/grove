import SwiftUI

/// Multi-step onboarding adapted for mobile — full-screen presentation.
/// Pages: Welcome, Capture type, Organize style, Goals, Ready.
struct MobileOnboardingView: View {
    @Environment(OnboardingService.self) private var onboarding
    @State private var page: OnboardingPage = .welcome
    @State private var selectedCapture: Set<CaptureType> = []
    @State private var selectedOrganize: OrganizeStyle?
    @State private var selectedGoals: Set<OnboardingGoal> = []
    @State private var navigatingForward = true

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: navigatingForward ? .trailing : .leading),
                removal: .move(edge: navigatingForward ? .leading : .trailing)
            ))
            .animation(.easeInOut(duration: 0.3), value: page)

            // Page indicator + navigation
            VStack(spacing: Spacing.lg) {
                pageIndicator

                HStack(spacing: Spacing.lg) {
                    if page != .welcome {
                        Button("Back") {
                            navigatingForward = false
                            withAnimation { goBack() }
                        }
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    if page == .ready {
                        Button("Get Started") {
                            completeOnboarding()
                        }
                        .font(.groveBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(Color.textPrimary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Button("Next") {
                            navigatingForward = true
                            withAnimation { goForward() }
                        }
                        .font(.groveBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                    }
                }
                .padding(.horizontal, Spacing.xl)
            }
            .padding(.bottom, Spacing.xl)
        }
        .padding(.top, Spacing.xl)
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingPage.allCases, id: \.self) { p in
                Circle()
                    .fill(p == page ? Color.textPrimary : Color.textMuted.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "leaf")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: Spacing.md) {
                Text("Welcome to Grove")
                    .font(.groveTitle)
                    .foregroundStyle(Color.textPrimary)

                Text("A thinking space for ideas that grow.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                featureRow(icon: "square.and.arrow.down", text: "Capture links, notes, and ideas")
                featureRow(icon: "tray.2", text: "Triage and organize into boards")
                featureRow(icon: "bubble.left.and.bubble.right", text: "Discuss ideas with AI")
                featureRow(icon: "arrow.triangle.branch", text: "Discover connections between ideas")
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 28)
            Text(text)
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Capture

    private var capturePage: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("What will you capture?")
                    .font(.groveTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Select all that apply")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: Spacing.md) {
                captureChip(.links, icon: "link", label: "Links & Articles")
                captureChip(.notes, icon: "note.text", label: "Notes & Ideas")
                captureChip(.courses, icon: "graduationcap", label: "Courses & Lectures")
            }
            .padding(.horizontal, Spacing.xl)
        }
    }

    private func captureChip(_ type: CaptureType, icon: String, label: String) -> some View {
        let isSelected = selectedCapture.contains(type)
        return Button {
            if isSelected {
                selectedCapture.remove(type)
            } else {
                selectedCapture.insert(type)
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                Text(label)
                    .font(.groveBody)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
            .padding(Spacing.md)
            .background(isSelected ? Color.bgCardHover : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.borderPrimary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Organize

    private var organizePage: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("How do you organize?")
                    .font(.groveTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Choose one approach")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: Spacing.md) {
                organizeChip(.byProject, icon: "folder", label: "By Project", description: "Group items into boards for each project")
                organizeChip(.byTopic, icon: "tag", label: "By Topic", description: "Organize by themes and subject areas")
                organizeChip(.figureItOut, icon: "sparkles", label: "Figure It Out", description: "Let AI suggest how to organize")
            }
            .padding(.horizontal, Spacing.xl)
        }
    }

    private func organizeChip(_ style: OrganizeStyle, icon: String, label: String, description: String) -> some View {
        let isSelected = selectedOrganize == style
        return Button {
            selectedOrganize = style
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.groveBody)
                    Text(description)
                        .font(.groveMeta)
                        .foregroundStyle(isSelected ? Color.textSecondary : Color.textMuted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
            .padding(Spacing.md)
            .background(isSelected ? Color.bgCardHover : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.borderPrimary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Goals

    private var goalsPage: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("What are your goals?")
                    .font(.groveTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Select all that apply")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: Spacing.md) {
                goalChip(.research, icon: "book", label: "Deep Research", description: "Build understanding of complex topics")
                goalChip(.journaling, icon: "pencil.and.scribble", label: "Reflection & Journaling", description: "Develop ideas through writing")
                goalChip(.aiThinking, icon: "brain", label: "AI-Assisted Thinking", description: "Use Dialectics to explore ideas")
            }
            .padding(.horizontal, Spacing.xl)
        }
    }

    private func goalChip(_ goal: OnboardingGoal, icon: String, label: String, description: String) -> some View {
        let isSelected = selectedGoals.contains(goal)
        return Button {
            if isSelected {
                selectedGoals.remove(goal)
            } else {
                selectedGoals.insert(goal)
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.groveBody)
                    Text(description)
                        .font(.groveMeta)
                        .foregroundStyle(isSelected ? Color.textSecondary : Color.textMuted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
            .padding(Spacing.md)
            .background(isSelected ? Color.bgCardHover : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.borderPrimary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ready

    private var readyPage: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: Spacing.md) {
                Text("You're all set!")
                    .font(.groveTitle)
                    .foregroundStyle(Color.textPrimary)

                Text("Start by capturing something — a link, a note, or an idea.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Summary of selections
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !selectedCapture.isEmpty {
                    summaryRow(icon: "square.and.arrow.down",
                               text: selectedCapture.map(\.displayLabel).joined(separator: ", "))
                }
                if let organize = selectedOrganize {
                    summaryRow(icon: "folder", text: organize.displayLabel)
                }
                if !selectedGoals.isEmpty {
                    summaryRow(icon: "target", text: selectedGoals.map(\.displayLabel).joined(separator: ", "))
                }
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func summaryRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20)
            Text(text)
                .font(.groveBodySecondary)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Navigation

    private func goForward() {
        switch page {
        case .welcome: page = .capture
        case .capture: page = .organize
        case .organize: page = .goals
        case .goals: page = .ready
        case .ready: break
        }
    }

    private func goBack() {
        switch page {
        case .welcome: break
        case .capture: page = .welcome
        case .organize: page = .capture
        case .goals: page = .organize
        case .ready: page = .goals
        }
    }

    private func completeOnboarding() {
        OnboardingPreferences.captureTypes = selectedCapture
        OnboardingPreferences.organizeStyle = selectedOrganize
        OnboardingPreferences.goals = selectedGoals
        onboarding.complete()
    }
}

// MARK: - Supporting types

private enum OnboardingPage: CaseIterable {
    case welcome, capture, organize, goals, ready
}

private extension CaptureType {
    var displayLabel: String {
        switch self {
        case .links: "Links"
        case .notes: "Notes"
        case .courses: "Courses"
        }
    }
}

private extension OrganizeStyle {
    var displayLabel: String {
        switch self {
        case .byProject: "By Project"
        case .byTopic: "By Topic"
        case .figureItOut: "Let AI decide"
        }
    }
}

private extension OnboardingGoal {
    var displayLabel: String {
        switch self {
        case .research: "Research"
        case .journaling: "Journaling"
        case .aiThinking: "AI Thinking"
        }
    }
}
