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

private enum OnboardingPage {
    case welcome
    case preferences
}

// MARK: - Flow View

struct OnboardingFlowView: View {
    @Environment(OnboardingService.self) private var onboarding

    @State private var page: OnboardingPage = .welcome
    @State private var selectedUseCases: Set<GroveUseCase> = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        onboarding.skip()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.groveBody)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Spacing.lg)
                    .padding(.trailing, Spacing.lg)
                }

                // Page content
                Group {
                    switch page {
                    case .welcome:
                        welcomePage
                    case .preferences:
                        preferencesPage
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
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
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // App icon
            Image("AppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
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

            Spacer()

            // Continue button
            Button("Continue") {
                page = .preferences
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, Spacing.xxl)
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(minHeight: 280)
    }

    // MARK: - Preferences Page

    private var preferencesPage: some View {
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

            // Get Started button
            Button("Get Started") {
                OnboardingPreferences.selectedUseCases = selectedUseCases
                onboarding.complete()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, Spacing.xxl)
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(minHeight: 280)
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

// MARK: - Flow Layout

/// A simple horizontal wrapping layout for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 {
                height += spacing
            }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            // Center row horizontally
            let rowWidth = row.enumerated().reduce(CGFloat(0)) { acc, pair in
                acc + pair.element.sizeThatFits(.unspecified).width + (pair.offset > 0 ? spacing : 0)
            }
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + (rows.last!.isEmpty ? 0 : spacing) > maxWidth {
                rows.append([subview])
                currentRowWidth = size.width
            } else {
                currentRowWidth += size.width + (rows.last!.isEmpty ? 0 : spacing)
                rows[rows.count - 1].append(subview)
            }
        }
        return rows
    }
}
