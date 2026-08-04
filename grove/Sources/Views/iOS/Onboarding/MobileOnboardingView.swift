import SwiftUI

/// First-launch welcome adapted for mobile — full-screen presentation.
/// One page: what Grove is, then straight into the app. (The coach-mark
/// guide is macOS-only, so mobile ends with a capture prompt instead.)
struct MobileOnboardingView: View {
    @Environment(OnboardingService.self) private var onboarding

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            welcomeContent

            Spacer()

            VStack(spacing: Spacing.md) {
                Text("Start by capturing something — a link, a note, or an idea.")
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.xl)
            }
            .padding(.bottom, Spacing.xl)
        }
        .padding(.top, Spacing.xl)
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
                featureRow(icon: "square.and.arrow.down", text: "Capture links and notes from anywhere")
                featureRow(icon: "envelope", text: "Follow newsletters and feeds in a quiet inbox")
                featureRow(icon: "tray.2", text: "Triage with a swipe — queue, file, or archive")
                featureRow(icon: "square.grid.2x2", text: "Group ideas into boards by project or topic")
                featureRow(icon: "bubble.left.and.bubble.right", text: "Think it through in chat with Grove")
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
