import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Background
    static let bgPrimary = Color("bgPrimary")
    static let bgSidebar = Color("bgSidebar")
    static let bgInspector = Color("bgInspector")
    static let bgCard = Color("bgCard")
    static let bgCardHover = Color("bgCardHover")
    static let bgInput = Color("bgInput")
    static let bgTagActive = Color("bgTagActive")

    // Text
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let textTertiary = Color("textTertiary")
    static let textMuted = Color("textMuted")
    static let textInverse = Color("textInverse")

    // Border
    static let borderPrimary = Color("borderPrimary")
    static let borderInput = Color("borderInput")
    static let borderTag = Color("borderTag")
    static let borderTagDashed = Color("borderTagDashed")

    // Accent
    static let accentSelection = Color("accentSelection")
    static let accentBadge = Color("accentBadge")
    static let barFillHigh = Color("barFillHigh")
    static let barFillMid = Color("barFillMid")
    static let barFillLow = Color("barFillLow")
    static let barTrack = Color("barTrack")
}

// MARK: - Typography

extension Font {
    /// Newsreader 30pt, weight 500 — Board titles
    static let groveTitle = Font.custom("Newsreader-Medium", size: 30)

    /// Newsreader 20pt, weight 500 — Item titles in inspector
    static let groveItemTitle = Font.custom("Newsreader-Medium", size: 20)

    /// IBM Plex Mono 11pt, weight 500 — Section headers (apply .textCase(.uppercase) and .tracking(1.2) separately)
    static let groveSectionHeader = Font.custom("IBMPlexMono-Medium", size: 11)

    /// IBM Plex Sans 14pt, weight 400 — Primary body text
    static let groveBody = Font.custom("IBMPlexSans-Regular", size: 14)

    /// IBM Plex Sans 13pt, weight 400 — Secondary body text
    static let groveBodySecondary = Font.custom("IBMPlexSans-Regular", size: 13)

    /// IBM Plex Sans 12pt, weight 400 — Small body text
    static let groveBodySmall = Font.custom("IBMPlexSans-Regular", size: 12)

    /// IBM Plex Mono 12pt, weight 400 — Tags
    static let groveTag = Font.custom("IBMPlexMono-Regular", size: 12)

    /// IBM Plex Mono 12pt, weight 400 — Metadata (timestamps, source URLs, counts)
    static let groveMeta = Font.custom("IBMPlexMono-Regular", size: 12)

    /// IBM Plex Mono 11pt, weight 600 — Badges
    static let groveBadge = Font.custom("IBMPlexMono-SemiBold", size: 11)

    /// IBM Plex Mono 13pt, weight 400 — Keyboard shortcuts
    static let groveShortcut = Font.custom("IBMPlexMono-Regular", size: 13)

    /// Newsreader 14pt italic — Ghost text / placeholder prompts
    static let groveGhostText = Font.custom("Newsreader-Italic", size: 14)

    /// IBM Plex Sans 15pt — Slightly larger body
    static let groveBodyLarge = Font.custom("IBMPlexSans-Regular", size: 15)

    /// IBM Plex Sans Medium 14pt — Emphasized body
    static let groveBodyMedium = Font.custom("IBMPlexSans-Medium", size: 14)

    /// IBM Plex Sans Light 14pt — Light body
    static let groveBodyLight = Font.custom("IBMPlexSans-Light", size: 14)

    /// Newsreader 24pt — Large titles
    static let groveTitleLarge = Font.custom("Newsreader-Medium", size: 24)

    /// Newsreader 14pt — Inline serif text
    static let groveSerif = Font.custom("Newsreader-Regular", size: 14)

    /// Newsreader SemiBold 20pt — Emphasized item title
    static let groveItemTitleBold = Font.custom("Newsreader-SemiBold", size: 20)
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 28
}

// MARK: - Layout

enum LayoutDimensions {
    static let sidebarWidth: CGFloat = 220
    static let inspectorWidth: CGFloat = 280
    static let sidebarPaddingH: CGFloat = 20
    static let sidebarPaddingTop: CGFloat = 28
    static let contentPaddingH: CGFloat = 28
    static let contentPaddingTop: CGFloat = 24
    static let inspectorPaddingH: CGFloat = 16
    static let inspectorPaddingTop: CGFloat = 24
}

// MARK: - View Modifiers

/// Section header modifier: uppercase, monospace, muted, tracked
struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.groveSectionHeader)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Color.textMuted)
    }
}

/// Selected item modifier: left-border + card background + subtle shadow
struct SelectedItemStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? Color.bgCard : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentSelection)
                        .frame(width: 2)
                }
            }
            .shadow(color: isSelected ? .black.opacity(0.04) : .clear, radius: 2, y: 1)
    }
}

extension View {
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }

    func selectedItemStyle(_ isSelected: Bool) -> some View {
        modifier(SelectedItemStyle(isSelected: isSelected))
    }
}
