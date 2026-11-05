import SwiftUI

// MARK: - Onboarding Button Style

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodyMedium)
            .foregroundStyle(Color.textInverse)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(isEnabled ? Color.textPrimary : Color.textSecondary)
            .clipShape(.rect(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Flow View

/// First-launch welcome card. One page: what Grove is, then hand off to the
/// interactive coach-mark guide for the actual walkthrough.
struct OnboardingFlowView: View {
    @Environment(OnboardingService.self) private var onboarding
    @Environment(CoachMarkService.self) private var coachMarks

    @State private var iconAppeared = false
    @State private var skipHovered = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation row
                HStack {
                    Spacer()
                    Button("Skip") {
                        onboarding.skip()
                    }
                    .buttonStyle(.plain)
                    .font(.groveBodySmall)
                    .foregroundStyle(skipHovered ? Color.textPrimary : Color.textTertiary)
                    .onHover { skipHovered = $0 }
                }
                .padding(.top, Spacing.md)
                .padding(.horizontal, Spacing.lg)

                welcomePage
            }
            .frame(maxWidth: 460)
            .background(Color.bgPrimary)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: Spacing.lg) {
            // App icon
            Group {
                #if os(macOS)
                if let nsImage = NSApplication.shared.applicationIconImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "leaf")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.textSecondary)
                }
                #else
                Image(systemName: "leaf")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.textSecondary)
                #endif
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
                    description: "File what you keep into boards by project or topic"
                )
                featureRow(
                    icon: "book",
                    description: "Read distraction-free and keep highlights"
                )
                featureRow(
                    icon: "rectangle.on.rectangle",
                    description: "Turn a highlight into a reflection, then a flashcard"
                )
                featureRow(
                    icon: "bubble.left.and.bubble.right",
                    description: "Think it through in Chat, grounded in your library"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Spacing.sm) {
                Button("Get Started") {
                    onboarding.complete()
                    coachMarks.startGuide()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])

                Text("A short tour will walk you through the basics.")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.lg)
    }

    // MARK: - Shared Components

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
}
