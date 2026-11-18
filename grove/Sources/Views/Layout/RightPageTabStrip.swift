import SwiftUI

// MARK: - Right Page Tabs

/// What the window's right page can show. The left page is what was collected
/// (a list, a source, a note); the right page is what is being made of it.
///
/// These are tabs, not toggles: picking one shows it, picking the one already
/// showing closes the page, and whatever a tab held — a half-written note, a
/// conversation — is still there when it is picked again.
enum RightPageTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Reflections on the source open in the reader. Offered only while a
    /// source is being read; the reader owns the panel itself.
    case reflections
    /// The quick note writer.
    case note
    /// Dialectics chat.
    case chat
    /// The inspector: metadata, boards, connections, backlinks.
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reflections: "Reflections"
        case .note: "Note"
        case .chat: "Chat"
        case .info: "Info"
        }
    }

    /// The menu shortcut that reaches this tab, where there is one.
    var shortcutHint: String? {
        switch self {
        case .chat: "\u{21E7}\u{2318}D"
        case .info: "\u{2318}]"
        case .reflections, .note: nil
        }
    }

    func helpText(isActive: Bool) -> String {
        let verb = isActive ? "Hide" : "Show"
        if let shortcutHint {
            return "\(verb) \(title) (\(shortcutHint))"
        }
        return "\(verb) \(title)"
    }
}

// MARK: - Tab Strip

/// The right page's tabs, set as words. Sits at the trailing end of the
/// window toolbar, directly above the page it switches, and replaces the
/// three separate write / chat / inspector toggles.
struct RightPageTabStrip: View {
    let tabs: [RightPageTab]
    let active: RightPageTab?
    var isAvailable: (RightPageTab) -> Bool = { _ in true }
    let onSelect: (RightPageTab) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(tabs) { tab in
                RightPageTabButton(
                    tab: tab,
                    isActive: tab == active,
                    action: { onSelect(tab) }
                )
                .disabled(!isAvailable(tab))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right page")
    }
}

private struct RightPageTabButton: View {
    let tab: RightPageTab
    let isActive: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var theme: GroveTheme { ThemeStore.shared.theme }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control)
    }

    /// Grove marks the active tab the way the sidebar marks a selection: a
    /// soft card and a hairline. Commonplace sets the tabs as tracked mono
    /// capitals and underlines the active one.
    private var showsPill: Bool {
        isActive && !theme.usesRules
    }

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(theme.usesRules ? .groveSectionHeader : .groveBodySmall)
                .tracking(theme.usesRules ? 1.2 : 0)
                .underline(theme.usesRules && isActive)
                .textCase(theme.usesRules ? .uppercase : nil)
                .foregroundStyle(isActive || isHovering ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Spacing.sm)
                .frame(height: 24)
                .background(shape.fill(showsPill ? Color.bgCard : Color.clear))
                .overlay {
                    if showsPill {
                        shape.stroke(Color.borderPrimary, lineWidth: 1)
                    }
                }
                #if os(iOS)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
                #endif
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .help(tab.helpText(isActive: isActive))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
