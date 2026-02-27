import SwiftUI

/// Inline nudge banner with message, item title, and action buttons.
/// Swipe-to-dismiss gesture supported via List swipe actions or manual dismissal.
struct MobileNudgeBanner: View {
    let nudge: Nudge
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: nudge.type == .resurface ? "arrow.counterclockwise" : "tray.full")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(nudge.message)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                if let item = nudge.targetItem {
                    Text(item.title)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

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
