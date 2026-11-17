import SwiftUI

/// The sidebar folded down to a strip: Today, Library and Following, then the
/// boards as the numbers their ⌘1–⌘9 shortcuts already give them.
///
/// It stands in for the sidebar whenever the sidebar is collapsed — which it
/// is while a source is being read, so the article and the right page get the
/// window's width — and keeps every destination one click away without
/// bringing the full column back.
struct SidebarSpine: View {
    static let width: CGFloat = 44

    @Binding var selection: SidebarItem?
    let boards: [Board]
    /// Called after a destination is picked, so the host can leave the reader.
    var onNavigate: () -> Void
    /// Bring the full sidebar back.
    var onExpand: () -> Void

    /// Only boards that have a number shortcut get a number here; the rest
    /// are in the full sidebar.
    private static let numberedBoardLimit = 9

    var body: some View {
        VStack(spacing: Spacing.xs) {
            SpineButton(title: "Today", isSelected: selection == .home, action: { go(.home) }) {
                mark(symbol: "sun.max", letter: "T")
            }
            SpineButton(title: "Library", isSelected: selection == .library, action: { go(.library) }) {
                mark(symbol: "books.vertical", letter: "L")
            }
            SpineButton(title: "Following", isSelected: selection == .newsletters, action: { go(.newsletters) }) {
                mark(symbol: "newspaper", letter: "F")
            }

            Rectangle()
                .fill(Color.borderPrimary)
                .frame(width: 20, height: 1)
                .padding(.vertical, Spacing.sm)
                .accessibilityHidden(true)

            ForEach(Array(boards.prefix(Self.numberedBoardLimit).enumerated()), id: \.element.id) { index, board in
                SpineButton(
                    title: board.title,
                    help: "\(board.title) (\u{2318}\(index + 1))",
                    isSelected: selection == .board(board.id),
                    action: { go(.board(board.id)) }
                ) {
                    Text("\(index + 1)")
                        .font(.groveMeta)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            SpineButton(title: "Show sidebar", isSelected: false, action: onExpand) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.vertical, Spacing.sm)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color.bgSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contents")
    }

    /// A destination's mark: its symbol in Grove, its initial in Commonplace.
    @ViewBuilder
    private func mark(symbol: String, letter: String) -> some View {
        if ThemeStore.shared.theme.usesGlyphs {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
        } else {
            Text(letter)
                .font(.groveMeta)
        }
    }

    private func go(_ destination: SidebarItem) {
        selection = destination
        onNavigate()
    }
}

/// One spine entry: the sidebar row's selection voice (soft card fill and a
/// hairline) at the size of a glyph.
private struct SpineButton<Glyph: View>: View {
    let title: String
    var help: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var glyph: Glyph

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control)
    }

    private var usesRules: Bool { ThemeStore.shared.theme.usesRules }

    private var fillColor: Color {
        if usesRules { return Color.clear }
        if isSelected { return Color.bgCard }
        if isHovering { return Color.bgCardHover.opacity(0.6) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(isSelected || isHovering ? Color.textPrimary : Color.textSecondary)
                .frame(width: 28, height: 28)
                .background(shape.fill(fillColor))
                .overlay {
                    if isSelected && !usesRules {
                        shape.stroke(Color.borderPrimary, lineWidth: 1)
                    }
                }
                .overlay(alignment: .leading) {
                    if isSelected && usesRules {
                        Rectangle()
                            .fill(Color.accentSelection)
                            .frame(width: 2)
                            .padding(.vertical, Spacing.xs)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
