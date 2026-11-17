import SwiftUI

/// The app's one filter chip, for every horizontal filter bar (library
/// boards, newsletter sources, directory topics, search result types):
/// mono type, `Radius.control` corners, hairline border, `bgTagActive` ink
/// fill with inverse text when active, so every filter bar reads as one
/// system. On iOS the tappable height reaches the 44pt minimum even though
/// the drawn chip stays compact.
struct FilterChip: View {
    let label: String
    var systemImage: String? = nil
    var count: Int? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.groveMeta)
                }
                Text(label)
                    .lineLimit(1)
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isActive ? Color.textInverse.opacity(0.7) : Color.textTertiary)
                }
            }
            .font(.groveTag)
            .foregroundStyle(isActive ? Color.textInverse : Color.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                isActive ? Color.bgTagActive : Color.bgCard,
                in: RoundedRectangle(cornerRadius: Radius.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
            )
            #if os(iOS)
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
