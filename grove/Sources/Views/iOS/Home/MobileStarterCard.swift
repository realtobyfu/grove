import SwiftUI

/// Tappable card showing a conversation starter prompt.
/// Tap navigates to chat with the seeded prompt.
struct MobileStarterCard: View {
    let bubble: PromptBubble
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(bubble.label)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text(bubble.prompt)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
