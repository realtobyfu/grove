import SwiftUI

/// The one Grove button. Ink fill for the main action of a surface
/// (`.primary`), hairline border for everything else (`.secondary`).
/// Square-ish 4pt corners at every size — never a capsule, no shadow,
/// no scale animation.
///
/// A call site that wants a full-width button applies
/// `.frame(maxWidth: .infinity)` to its label.
struct GroveButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    enum Size { case regular, compact }

    var kind: Kind
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        GroveButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

extension ButtonStyle where Self == GroveButtonStyle {
    static func grove(_ kind: GroveButtonStyle.Kind, size: GroveButtonStyle.Size = .regular) -> GroveButtonStyle {
        GroveButtonStyle(kind: kind, size: size)
    }
}

private struct GroveButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: GroveButtonStyle.Kind
    let size: GroveButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control)
    }

    var body: some View {
        drawn
            // Tappable area: at least 44pt high on iOS even when the drawn
            // compact button is shorter.
            #if os(iOS)
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }

    private var drawn: some View {
        configuration.label
            .font(size == .regular ? .groveBodyMedium : .groveBodySmall)
            .foregroundStyle(kind == .primary ? Color.textInverse : Color.textPrimary)
            .padding(.horizontal, size == .regular ? Spacing.lg : Spacing.md)
            .padding(.vertical, size == .regular ? Spacing.sm : Spacing.xs)
            #if os(iOS)
            .frame(minHeight: size == .regular ? LayoutDimensions.minTouchTarget : nil)
            #endif
            .background(background)
            .overlay {
                if kind == .secondary {
                    shape.strokeBorder(Color.borderInput, lineWidth: 1)
                }
            }
            .clipShape(shape)
            .opacity(kind == .primary && configuration.isPressed ? 0.85 : 1)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            Color.textPrimary
        case .secondary:
            ZStack {
                Color.bgCard
                if configuration.isPressed {
                    Color.textPrimary.opacity(0.06)
                }
            }
        }
    }
}
