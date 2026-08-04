import SwiftUI

/// Small monochrome button used for inline actions (Add feed, Subscribe).
/// Same 4pt-radius language as other inline buttons — square-ish edges, ink
/// fill when prominent, hairline border otherwise. Capsules are off-brand.
struct GroveCompactButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodySmall)
            .foregroundStyle(prominent ? Color.textInverse : Color.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 1)
            .background(prominent ? Color.textPrimary : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(prominent ? Color.clear : Color.borderPrimary, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
