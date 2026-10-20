import SwiftUI

struct LearningPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodyMedium)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, Spacing.md)
            .foregroundStyle(Color.textInverse)
            .background(Color.textPrimary.opacity(isEnabled ? 1 : 0.45))
            .clipShape(.rect(cornerRadius: LayoutDimensions.cardCornerRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct LearningSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodySmall)
            .frame(minHeight: 44)
            .padding(.horizontal, Spacing.md)
            .foregroundStyle(Color.textPrimary)
            .background(configuration.isPressed ? Color.bgInput : Color.bgCard)
            .clipShape(.rect(cornerRadius: LayoutDimensions.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                    .stroke(Color.borderInput, lineWidth: 1)
            }
    }
}
