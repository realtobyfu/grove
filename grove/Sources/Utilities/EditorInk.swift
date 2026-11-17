#if os(macOS)
import AppKit
typealias PlatformInkColor = NSColor
#else
import UIKit
typealias PlatformInkColor = UIColor
#endif

/// The design system's ink, as platform colours.
///
/// Text storage attributes and custom `draw` code cannot take a SwiftUI
/// `Color`, which is how the editors ended up on `labelColor` and friends —
/// a different black from every other surface. These resolve the same asset
/// colours `Color.textPrimary` … `Color.textMuted` do, so the editor, the
/// rendered markdown and the rest of the app share one set of inks and follow
/// any change made to the assets.
///
/// Each colour is created once per theme: the live editor diffs attribute
/// runs to find the paragraphs that actually changed, and identical instances
/// make that comparison exact. An editor that is already open takes a newly
/// chosen theme's ink the next time it restyles.
@MainActor
enum EditorInk {
    private struct Palette {
        let primary: PlatformInkColor
        let secondary: PlatformInkColor
        let tertiary: PlatformInkColor
        let muted: PlatformInkColor
        let rule: PlatformInkColor
        let codeWash: PlatformInkColor

        init(theme: GroveTheme) {
            primary = EditorInk.named("textPrimary", in: theme, fallback: EditorInk.systemPrimary)
            secondary = EditorInk.named("textSecondary", in: theme, fallback: EditorInk.systemSecondary)
            tertiary = EditorInk.named("textTertiary", in: theme, fallback: EditorInk.systemTertiary)
            muted = EditorInk.named("textMuted", in: theme, fallback: EditorInk.systemTertiary)
            rule = EditorInk.named("borderPrimary", in: theme, fallback: EditorInk.systemTertiary)
            codeWash = EditorInk.named("bgInput", in: theme, fallback: EditorInk.systemWash)
        }
    }

    private static let grovePalette = Palette(theme: .grove)
    private static let commonplacePalette = Palette(theme: .commonplace)

    private static var palette: Palette {
        switch ThemeStore.shared.theme {
        case .grove: grovePalette
        case .commonplace: commonplacePalette
        }
    }

    static var primary: PlatformInkColor { palette.primary }
    static var secondary: PlatformInkColor { palette.secondary }
    static var tertiary: PlatformInkColor { palette.tertiary }
    static var muted: PlatformInkColor { palette.muted }
    /// Hairlines drawn in the text: the quote rail and dividers.
    static var rule: PlatformInkColor { palette.rule }
    /// The inset wash behind inline code and code blocks.
    static var codeWash: PlatformInkColor { palette.codeWash }

    private static func named(_ token: String, in theme: GroveTheme, fallback: PlatformInkColor) -> PlatformInkColor {
        PlatformInkColor(named: theme.assetName(token)) ?? fallback
    }

    #if os(macOS)
    private static var systemPrimary: NSColor { .labelColor }
    private static var systemSecondary: NSColor { .secondaryLabelColor }
    private static var systemTertiary: NSColor { .tertiaryLabelColor }
    private static var systemWash: NSColor { .quaternaryLabelColor }
    #else
    private static var systemPrimary: UIColor { .label }
    private static var systemSecondary: UIColor { .secondaryLabel }
    private static var systemTertiary: UIColor { .tertiaryLabel }
    private static var systemWash: UIColor { .quaternaryLabel }
    #endif
}
