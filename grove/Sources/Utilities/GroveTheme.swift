import SwiftUI
import Observation

// MARK: - Theme

/// Grove's two looks. The layout is the same in both; a theme decides the
/// paper and ink, and a small number of habits — whether a destination is
/// marked by a glyph or a word, whether entries sit on cards or between rules.
enum GroveTheme: String, CaseIterable, Identifiable, Sendable {
    /// The look Grove has always had: neutral greys, SF Symbols, soft cards.
    case grove
    /// A commonplace book: warm paper, words and numerals in place of icons,
    /// hairline rules in place of boxes.
    case commonplace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grove: "Grove"
        case .commonplace: "Commonplace"
        }
    }

    var summary: String {
        switch self {
        case .grove: "Neutral greys, icons and soft cards."
        case .commonplace: "Warm paper, words in place of icons, rules in place of boxes."
        }
    }

    // MARK: Palette

    /// The colour tokens every theme supplies. Each one is an asset; the
    /// Commonplace counterpart carries the suffix below.
    static let colorTokens: [String] = [
        "bgPrimary", "bgSidebar", "bgInspector", "bgCard", "bgCardHover", "bgInput", "bgTagActive",
        "textPrimary", "textSecondary", "textTertiary", "textMuted", "textInverse",
        "borderPrimary", "borderInput", "borderTag", "borderTagDashed",
        "accentSelection", "accentBadge", "barFillHigh", "barFillMid", "barFillLow",
    ]

    /// The asset that holds `token` in this theme.
    func assetName(_ token: String) -> String {
        switch self {
        case .grove: token
        case .commonplace: token + "Commonplace"
        }
    }

    // MARK: Habits

    /// Destinations and item types are marked with SF Symbols. When false
    /// they are set as words and numerals instead.
    var usesGlyphs: Bool {
        self == .grove
    }

    /// List entries are separated by hairline rules rather than sitting on
    /// filled, rounded cards.
    var usesRules: Bool {
        self == .commonplace
    }
}

// MARK: - Store

/// The theme in use, for everything that draws.
///
/// The colour tokens (`Color.bgPrimary` and the rest) read it on every access,
/// and it is observable, so a view that reads a token or `ThemeStore.shared
/// .theme` in its body is redrawn when the theme changes — no call site has
/// to pass the theme along.
///
/// `@unchecked Sendable`: the tokens are plain static properties and can be
/// read from anywhere, so this cannot be bound to the main actor. The one
/// stored value is only ever written on the main actor (`select`), from
/// Settings.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    private(set) var theme: GroveTheme

    private init() {
        theme = AppearanceSettings.theme
    }

    /// Switch themes and remember the choice.
    @MainActor
    func select(_ newTheme: GroveTheme) {
        guard newTheme != theme else { return }
        theme = newTheme
        AppearanceSettings.theme = newTheme
    }

    /// The colour `token` has in the current theme.
    static func color(_ token: String) -> Color {
        Color(shared.theme.assetName(token))
    }
}
