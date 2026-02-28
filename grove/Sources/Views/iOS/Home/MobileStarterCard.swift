import SwiftUI

/// Tappable card showing a conversation starter prompt.
/// The tap action is supplied by the parent so the card can open chat directly or present a chooser.
struct MobileStarterCard: View {
    let bubble: PromptBubble
    var showsDisclosureIndicator = false
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

                if showsDisclosureIndicator {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(.top, Spacing.xs)
                }
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
