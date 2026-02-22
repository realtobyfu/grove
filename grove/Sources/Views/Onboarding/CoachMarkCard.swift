import SwiftUI

enum CoachMarkArrowEdge {
    case top
    case bottom
    case leading
    case trailing
}

struct CoachMarkCard: View {
    let title: String
    let description: String
    let actionLabel: String
    let arrowEdge: CoachMarkArrowEdge
    let onAction: () -> Void
    let onSkip: () -> Void

    private let arrowSize: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            Text(description)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: Spacing.md) {
                Button(actionLabel) {
                    onAction()
                }
                .font(.groveBodySmall)
                .foregroundStyle(Color.textInverse)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.textPrimary)
                .clipShape(.rect(cornerRadius: 6))

                Button("Skip") {
                    onSkip()
                }
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
                .buttonStyle(.plain)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.lg)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 260)
    }
}
