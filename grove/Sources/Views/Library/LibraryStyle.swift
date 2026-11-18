import SwiftUI
#if os(iOS)
import UIKit
#endif

// Tokens the Library page needs that DesignTokens does not have yet. They are
// kept here, named and shaped like the shared ones, so a theme pass can move
// or restyle them in one place.

extension Font {
    /// IBM Plex Sans Medium at `groveBodySecondary`'s size: 13pt (macOS),
    /// 15pt (iPhone), 14pt (iPad). The matched words inside a find snippet,
    /// which is set in `groveBodySecondary`: the match is marked by weight.
    #if os(macOS)
    static let groveSnippetMatch = Font.custom("IBMPlexSans-Medium", size: 13)
    #else
    @MainActor static let groveSnippetMatch = Font.custom(
        "IBMPlexSans-Medium",
        size: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 15,
        relativeTo: .subheadline
    )
    #endif
}

/// Fixed measures of the Library page that are not on the spacing scale.
/// Views that set type in these columns scale them with `@ScaledMetric`.
enum LibraryMetrics {
    /// Height of the find field.
    static let findFieldHeight: CGFloat = 40
    /// Width of the type column where types are set as words (Commonplace):
    /// room for the longest type word in tracked 11pt mono capitals
    /// ("REFLECT.").
    static let typeColumnWidth: CGFloat = 72
    /// Width of the type column where types are set as glyphs (Grove): the
    /// 20pt gutter the inbox rows give their type icon.
    static let typeGlyphColumnWidth: CGFloat = 20
    /// Least width of the date column, so dates share a right edge and a
    /// left one for the common case ("Nov 11").
    static let dateColumnMinWidth: CGFloat = 52
    /// Most width a board name may take before it is truncated in a row.
    static let boardColumnMaxWidth: CGFloat = 180
    /// Vertical inset of a count badge and of the hover action's chip.
    static let badgeInsetV: CGFloat = 3
    /// Clearance kept under the list for the multi-select action bar.
    static let actionBarClearance: CGFloat = 52
}
