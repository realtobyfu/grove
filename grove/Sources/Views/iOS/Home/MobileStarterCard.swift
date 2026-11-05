import SwiftUI

/// Tappable card for Today's "New Conversation" fallback, shown when there is
/// no starter. Real starters use `StarterCard`.
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
            .frame(minHeight: LayoutDimensions.minTouchTarget, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}
