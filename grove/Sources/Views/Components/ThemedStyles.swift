import SwiftUI

// The places a theme's habits show up in content, as opposed to chrome:
// how an item's type is marked, and what a list entry sits on. Views use
// these instead of branching on the theme themselves.

// MARK: - Item Type Mark

/// An item's type, marked the theme's way: its SF Symbol in Grove, a short
/// word in tracked mono capitals in Commonplace.
struct ItemTypeMark: View {
    let type: ItemType
    /// The word Commonplace sets, and what assistive technology reads in
    /// either theme ("Article", "PDF", "Note").
    let label: String

    var body: some View {
        if ThemeStore.shared.theme.usesGlyphs {
            Image(systemName: type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .accessibilityLabel(label)
        } else {
            Text(label)
                .sectionHeaderStyle()
                .lineLimit(1)
        }
    }
}

// MARK: - Entry Container

/// What a list entry sits on: a filled, rounded card in Grove; nothing but a
/// hairline above and below in Commonplace.
struct EntryStyle: ViewModifier {
    func body(content: Content) -> some View {
        if ThemeStore.shared.theme.usesRules {
            content
                .overlay(alignment: .top) { EntryRule() }
                .overlay(alignment: .bottom) { EntryRule() }
        } else {
            content
                .modifier(CardStyle(cornerRadius: Radius.card, background: Color.bgCard))
        }
    }
}

private struct EntryRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderPrimary)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A card in Grove, ruled in Commonplace. For list entries; sheets,
    /// popovers and bubbles keep `cardStyle()` in both themes.
    func entryStyle() -> some View {
        modifier(EntryStyle())
    }
}
