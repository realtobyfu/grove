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
/// Each colour is created once: the live editor diffs attribute runs to find
/// the paragraphs that actually changed, and identical instances make that
/// comparison exact.
@MainActor
enum EditorInk {
    static let primary = named("textPrimary", fallback: systemPrimary)
    static let secondary = named("textSecondary", fallback: systemSecondary)
    static let tertiary = named("textTertiary", fallback: systemTertiary)
    static let muted = named("textMuted", fallback: systemTertiary)
    /// Hairlines drawn in the text: the quote rail and dividers.
    static let rule = named("borderPrimary", fallback: systemTertiary)
    /// The inset wash behind inline code and code blocks.
    static let codeWash = named("bgInput", fallback: systemWash)

    private static func named(_ name: String, fallback: PlatformInkColor) -> PlatformInkColor {
        PlatformInkColor(named: name) ?? fallback
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
