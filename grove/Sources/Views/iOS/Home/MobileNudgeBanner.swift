import SwiftUI

/// Inline stale-inbox nudge banner with message and action buttons.
/// Swipe-to-dismiss gesture supported via List swipe actions or manual dismissal.
struct MobileNudgeBanner: View {
    let nudge: Nudge
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "tray.full")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32)

            Text(nudge.message)
                .font(.groveBodySecondary)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.sm) {
                Button("Open", action: onOpen)
                    .font(.groveBodySecondary)
                    .fontWeight(.medium)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(minWidth: LayoutDimensions.minTouchTarget,
                       minHeight: LayoutDimensions.minTouchTarget)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                .stroke(Color.borderPrimary, lineWidth: 1)
        }
    }
}
