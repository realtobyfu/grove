import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import grove

/// The two themes: which asset holds each colour, that every one of those
/// assets exists, and that the reader page takes its paper from the theme.
struct GroveThemeTests {

    // MARK: - Palette

    @Test func groveReadsTheAssetOfTheSameName() {
        #expect(GroveTheme.grove.assetName("bgPrimary") == "bgPrimary")
        #expect(GroveTheme.commonplace.assetName("bgPrimary") == "bgPrimaryCommonplace")
    }

    @Test func tokenListHasNoDuplicates() {
        #expect(Set(GroveTheme.colorTokens).count == GroveTheme.colorTokens.count)
    }

    #if os(macOS)
    /// A token with no asset draws as nothing at all, silently. This is the
    /// check that every colour both themes name is really in the catalog.
    @Test func everyTokenHasAnAssetInBothThemes() {
        // Only meaningful where the app's asset catalog is the main bundle's
        // (tests hosted in the app). Elsewhere there is nothing to look in.
        guard NSColor(named: "bgPrimary") != nil else { return }
        for theme in GroveTheme.allCases {
            for token in GroveTheme.colorTokens {
                let name = theme.assetName(token)
                #expect(NSColor(named: name) != nil, "missing colour asset \(name)")
            }
        }
    }
    #endif

    // MARK: - Habits

    @Test func eachThemeKeepsItsHabits() {
        #expect(GroveTheme.grove.usesGlyphs)
        #expect(!GroveTheme.grove.usesRules)
        #expect(!GroveTheme.commonplace.usesGlyphs)
        #expect(GroveTheme.commonplace.usesRules)
    }

    @Test func themesSurviveTheirStoredForm() {
        for theme in GroveTheme.allCases {
            #expect(GroveTheme(rawValue: theme.rawValue) == theme)
        }
        #expect(GroveTheme(rawValue: "sepia") == nil)
    }

    // MARK: - Reader page

    private func article() -> ReadableArticle {
        ReadableArticle(
            title: "A Field Guide to Moss",
            byline: "Ada Lovelace",
            contentHTML: "<p>Moss grows where little else will.</p>",
            textContent: "Moss grows where little else will.",
            length: 34,
            excerpt: nil,
            sourceURLString: "https://example.com/essays/moss",
            extractedAt: Date(timeIntervalSince1970: 1_700_000_000),
            wordCount: 1_200
        )
    }

    private func page(theme: GroveTheme, isDark: Bool = false) -> String {
        ReaderTemplate.page(
            article: article(),
            typography: ReaderTypographySettings(),
            isDark: isDark,
            readMinutes: 7,
            theme: theme
        )
    }

    @Test func theReaderPageDefaultsToGrovePaper() {
        let html = ReaderTemplate.page(
            article: article(),
            typography: ReaderTypographySettings(),
            isDark: false,
            readMinutes: 7
        )
        #expect(html.contains("--bg: #FAFAFA;"))
        #expect(!html.contains("--bg: #F9F7F1;"))
    }

    @Test func commonplaceGivesTheReaderWarmPaperInBothSchemes() {
        let html = page(theme: .commonplace)
        #expect(html.contains("--bg: #F9F7F1;"))
        #expect(html.contains("--fg: #1C1A17;"))
        #expect(html.contains("--bg: #13110E;"))
        #expect(!html.contains("--bg: #FAFAFA;"))
        #expect(!html.contains("--bg: #111111;"))
    }

    @Test func theSyntaxInksAreTheSameInEveryTheme() {
        for theme in GroveTheme.allCases {
            let html = page(theme: theme)
            #expect(html.contains("--tok-kw: #8A3D62;"))
            #expect(html.contains("--tok-kw: #D98FB4;"))
            #expect(html.contains("--highlight-wash: rgba(0, 0, 0, 0.08);"))
        }
    }
}
