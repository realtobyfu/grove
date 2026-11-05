import SwiftUI

/// First-launch welcome adapted for mobile — full-screen presentation.
/// One page: what Grove is, then straight into the app. (The coach-mark
/// guide is macOS-only, so mobile ends with a capture prompt instead.)
struct MobileOnboardingView: View {
    @Environment(OnboardingService.self) private var onboarding

    var body: some View {
        VStack(spacing: 0) {
            // Get Started is the only way out of the cover, so at large
            // Dynamic Type the welcome scrolls rather than pushing it off screen.
            ViewThatFits(in: .vertical) {
                welcomeContent
                ScrollView { welcomeContent }
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: Spacing.md) {
                Text("Start on Today: paste a link or type a note.")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Button {
                    onboarding.complete()
                } label: {
                    Text("Get Started")
                        .font(.groveBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textInverse)
                        .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.xl)
            }
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: 520)
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary)
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
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
                featureRow(icon: "square.and.arrow.down", text: "Capture on Today, or share from any app")
                featureRow(icon: "tray.2", text: "Swipe inbox items left to keep or file, right to drop")
                featureRow(icon: "square.grid.2x2", text: "Group what you keep into boards by project or topic")
                featureRow(icon: "rectangle.on.rectangle", text: "Turn a highlight into a reflection, then a flashcard")
                featureRow(icon: "bubble.left.and.bubble.right", text: "Think it through in Chat with Grove")
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
}
