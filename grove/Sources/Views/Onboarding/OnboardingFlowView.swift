import SwiftUI

// MARK: - Flow View

/// First-launch welcome card. One page: what Grove is and how it works.
struct OnboardingFlowView: View {
    @Environment(OnboardingService.self) private var onboarding

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
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
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
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
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
                }
                .buttonStyle(.grove(.primary))
                .keyboardShortcut(.return, modifiers: [])
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
