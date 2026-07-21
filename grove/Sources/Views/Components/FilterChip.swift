import SwiftUI

/// Shared filter chip for horizontal filter bars (newsletter sources,
/// directory topics). Identical language to the library's board chips —
/// mono type, 4pt radius, hairline border, `bgTagActive` fill when active —
/// so every filter bar in the app reads as one system.
struct FilterChip: View {
    let label: String
    var count: Int? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? Color.bgTagActive : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .frame(minHeight: 32)
        #endif
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
