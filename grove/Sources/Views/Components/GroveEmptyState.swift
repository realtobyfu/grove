import SwiftUI

/// The brand empty state: one serif line, one muted line, and an optional
/// single action. Same type and spacing as the empty-board note in
/// `MobileLibraryView`, so an empty screen reads like a quiet margin note
/// rather than a system placeholder. Callers supply the horizontal inset,
/// since it differs between list rows and plain stacks.
struct GroveEmptyState: View {
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.groveSerif)
                .foregroundStyle(Color.textSecondary)
            Text(detail)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textMuted)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.grove(.primary))
                    .padding(.top, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}
