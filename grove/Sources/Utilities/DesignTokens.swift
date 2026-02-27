import SwiftUI
#if os(iOS)
import UIKit
#endif

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

// MARK: - Platform Detection

#if os(iOS)
/// Device idiom is immutable at runtime. @MainActor required by UIDevice in Swift 6.
@MainActor
private enum Platform {
    static let isIPad = UIDevice.current.userInterfaceIdiom == .pad
}
#endif

// MARK: - Typography
//
// Font sizes per platform (from mobile-spec.md §6):
//   Token              | macOS | iPhone | iPad
//   groveTitle         | 30pt  | 28pt   | 30pt
//   groveItemTitle     | 20pt  | 18pt   | 20pt
//   groveBody          | 14pt  | 16pt   | 15pt
//   groveBodySecondary | 13pt  | 15pt   | 14pt
//   groveBodySmall     | 12pt  | 13pt   | 12pt
//   groveMeta          | 12pt  | 13pt   | 12pt
//   groveSectionHeader | 11pt  | 12pt   | 11pt
//
// On iOS, all fonts use Font.custom(_:size:relativeTo:) for Dynamic Type scaling.
// iOS font statics are @MainActor because they read UIDevice idiom at init time.
// This is safe: fonts are only accessed from SwiftUI view bodies (which are @MainActor).

extension Font {
    /// Newsreader 30pt (macOS/iPad), 28pt (iPhone) — Board titles
    #if os(macOS)
    static let groveTitle = Font.custom("Newsreader-Medium", size: 30)
    #else
    @MainActor static let groveTitle = Font.custom("Newsreader-Medium", size: Platform.isIPad ? 30 : 28, relativeTo: .title)
    #endif

    /// Newsreader 20pt (macOS/iPad), 18pt (iPhone) — Item titles in inspector
    #if os(macOS)
    static let groveItemTitle = Font.custom("Newsreader-Medium", size: 20)
    #else
    @MainActor static let groveItemTitle = Font.custom("Newsreader-Medium", size: Platform.isIPad ? 20 : 18, relativeTo: .title2)
    #endif

    /// IBM Plex Mono 11pt (macOS/iPad), 12pt (iPhone) — Section headers (apply .textCase(.uppercase) and .tracking(1.2) separately)
    #if os(macOS)
    static let groveSectionHeader = Font.custom("IBMPlexMono-Medium", size: 11)
    #else
    @MainActor static let groveSectionHeader = Font.custom("IBMPlexMono-Medium", size: Platform.isIPad ? 11 : 12, relativeTo: .caption2)
    #endif

    /// IBM Plex Sans 14pt (macOS), 16pt (iPhone), 15pt (iPad) — Primary body text
    #if os(macOS)
    static let groveBody = Font.custom("IBMPlexSans-Regular", size: 14)
    #else
    @MainActor static let groveBody = Font.custom("IBMPlexSans-Regular", size: Platform.isIPad ? 15 : 16, relativeTo: .body)
    #endif

    /// IBM Plex Sans 13pt (macOS), 15pt (iPhone), 14pt (iPad) — Secondary body text
    #if os(macOS)
    static let groveBodySecondary = Font.custom("IBMPlexSans-Regular", size: 13)
    #else
    @MainActor static let groveBodySecondary = Font.custom("IBMPlexSans-Regular", size: Platform.isIPad ? 14 : 15, relativeTo: .subheadline)
    #endif

    /// IBM Plex Sans 12pt (macOS/iPad), 13pt (iPhone) — Small body text
    #if os(macOS)
    static let groveBodySmall = Font.custom("IBMPlexSans-Regular", size: 12)
    #else
    @MainActor static let groveBodySmall = Font.custom("IBMPlexSans-Regular", size: Platform.isIPad ? 12 : 13, relativeTo: .footnote)
    #endif

    /// IBM Plex Mono 12pt (macOS/iPad), 13pt (iPhone) — Tags
    #if os(macOS)
    static let groveTag = Font.custom("IBMPlexMono-Regular", size: 12)
    #else
    @MainActor static let groveTag = Font.custom("IBMPlexMono-Regular", size: Platform.isIPad ? 12 : 13, relativeTo: .caption)
    #endif

    /// IBM Plex Mono 12pt (macOS/iPad), 13pt (iPhone) — Metadata (timestamps, source URLs, counts)
    #if os(macOS)
    static let groveMeta = Font.custom("IBMPlexMono-Regular", size: 12)
    #else
    @MainActor static let groveMeta = Font.custom("IBMPlexMono-Regular", size: Platform.isIPad ? 12 : 13, relativeTo: .caption)
    #endif

    /// IBM Plex Mono 11pt (macOS/iPad), 12pt (iPhone) — Badges
    #if os(macOS)
    static let groveBadge = Font.custom("IBMPlexMono-SemiBold", size: 11)
    #else
    @MainActor static let groveBadge = Font.custom("IBMPlexMono-SemiBold", size: Platform.isIPad ? 11 : 12, relativeTo: .caption2)
    #endif

    /// IBM Plex Mono 13pt — Keyboard shortcuts
    #if os(macOS)
    static let groveShortcut = Font.custom("IBMPlexMono-Regular", size: 13)
    #else
    @MainActor static let groveShortcut = Font.custom("IBMPlexMono-Regular", size: 13, relativeTo: .caption)
    #endif

    /// Newsreader 14pt (macOS), 16pt (iPhone), 15pt (iPad) italic — Ghost text / placeholder prompts
    #if os(macOS)
    static let groveGhostText = Font.custom("Newsreader-Italic", size: 14)
    #else
    @MainActor static let groveGhostText = Font.custom("Newsreader-Italic", size: Platform.isIPad ? 15 : 16, relativeTo: .body)
    #endif

    /// IBM Plex Sans 15pt (macOS), 17pt (iPhone), 16pt (iPad) — Slightly larger body
    #if os(macOS)
    static let groveBodyLarge = Font.custom("IBMPlexSans-Regular", size: 15)
    #else
    @MainActor static let groveBodyLarge = Font.custom("IBMPlexSans-Regular", size: Platform.isIPad ? 16 : 17, relativeTo: .body)
    #endif

    /// IBM Plex Sans Medium 14pt (macOS), 16pt (iPhone), 15pt (iPad) — Emphasized body
    #if os(macOS)
    static let groveBodyMedium = Font.custom("IBMPlexSans-Medium", size: 14)
    #else
    @MainActor static let groveBodyMedium = Font.custom("IBMPlexSans-Medium", size: Platform.isIPad ? 15 : 16, relativeTo: .body)
    #endif

    /// IBM Plex Sans Light 14pt (macOS), 16pt (iPhone), 15pt (iPad) — Light body
    #if os(macOS)
    static let groveBodyLight = Font.custom("IBMPlexSans-Light", size: 14)
    #else
    @MainActor static let groveBodyLight = Font.custom("IBMPlexSans-Light", size: Platform.isIPad ? 15 : 16, relativeTo: .body)
    #endif

    /// Newsreader 24pt (macOS/iPad), 22pt (iPhone) — Large titles
    #if os(macOS)
    static let groveTitleLarge = Font.custom("Newsreader-Medium", size: 24)
    #else
    @MainActor static let groveTitleLarge = Font.custom("Newsreader-Medium", size: Platform.isIPad ? 24 : 22, relativeTo: .title)
    #endif

    /// Newsreader 14pt (macOS), 16pt (iPhone), 15pt (iPad) — Inline serif text
    #if os(macOS)
    static let groveSerif = Font.custom("Newsreader-Regular", size: 14)
    #else
    @MainActor static let groveSerif = Font.custom("Newsreader-Regular", size: Platform.isIPad ? 15 : 16, relativeTo: .body)
    #endif

    /// Newsreader SemiBold 20pt (macOS/iPad), 18pt (iPhone) — Emphasized item title
    #if os(macOS)
    static let groveItemTitleBold = Font.custom("Newsreader-SemiBold", size: 20)
    #else
    @MainActor static let groveItemTitleBold = Font.custom("Newsreader-SemiBold", size: Platform.isIPad ? 20 : 18, relativeTo: .title2)
    #endif
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

/// Card container modifier: rounded background + border overlay
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 8
    var background: Color = .bgCard

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
    }
}

extension View {
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }

    func selectedItemStyle(_ isSelected: Bool) -> some View {
        modifier(SelectedItemStyle(isSelected: isSelected))
    }

    func cardStyle(cornerRadius: CGFloat = 8, background: Color = .bgCard) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, background: background))
    }
}
