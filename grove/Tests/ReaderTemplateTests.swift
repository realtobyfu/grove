import Foundation
import JavaScriptCore
import Testing
@testable import grove

/// `ReaderTemplate`'s Swift side: the reader page it builds, the JavaScript
/// strings it emits, and the contracts those strings share with the app
/// (escaping, the selection payload, live typography/theme updates).
struct ReaderTemplateTests {

    // MARK: - Fixtures

    private func article(
        title: String = "A Field Guide to Moss",
        byline: String? = "Ada Lovelace",
        content: String = "<p>Moss grows where little else will.</p>",
        source: String? = "https://example.com/essays/moss?ref=feed&utm=1",
        wordCount: Int = 1_200
    ) -> ReadableArticle {
        ReadableArticle(
            title: title,
            byline: byline,
            contentHTML: content,
            textContent: "Moss grows where little else will.",
            length: 34,
            excerpt: nil,
            sourceURLString: source,
            extractedAt: Date(timeIntervalSince1970: 1_700_000_000),
            wordCount: wordCount
        )
    }

    private func page(
        _ article: ReadableArticle,
        typography: ReaderTypographySettings = ReaderTypographySettings(),
        isDark: Bool = false,
        readMinutes: Int = 7
    ) -> String {
        ReaderTemplate.page(article: article, typography: typography, isDark: isDark, readMinutes: readMinutes)
    }

    /// The text between `start` and the next `end`, or nil.
    private func slice(_ text: String, from start: String, to end: String) -> String? {
        guard let lower = text.range(of: start)?.upperBound,
              let upper = text.range(of: end, range: lower..<text.endIndex)?.lowerBound
        else { return nil }
        return String(text[lower..<upper])
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - Page: theme

    @Test(arguments: [true, false])
    func pageCarriesTheRequestedTheme(isDark: Bool) {
        let html = page(article(), isDark: isDark)
        let expected = isDark ? "dark" : "light"
        #expect(html.contains("<html data-grove-theme=\"\(expected)\">"))
        #expect(occurrences(of: "<html", in: html) == 1)
    }

    @Test func pageDefinesBothExplicitThemesAndTheSystemFallback() throws {
        let html = page(article())
        let dark = try #require(slice(html, from: ":root[data-grove-theme=\"dark\"] {", to: "}"))
        let light = try #require(slice(html, from: ":root[data-grove-theme=\"light\"] {", to: "}"))
        #expect(dark.contains("--bg: #111111;"))
        #expect(dark.contains("--fg: #E8E8E8;"))
        #expect(light.contains("--bg: #FAFAFA;"))
        #expect(light.contains("--fg: #1A1A1A;"))
        #expect(html.contains("@media (prefers-color-scheme: dark)"))
    }

    // MARK: - Page: base URL

    @Test func pageBaseHrefIsTheEscapedSourceURL() {
        let html = page(article())
        #expect(html.contains("<base href=\"https://example.com/essays/moss?ref=feed&amp;utm=1\">"))
        #expect(occurrences(of: "<base ", in: html) == 1)
    }

    @Test func pageWithoutSourceURLHasNoBaseTagAndNoHost() {
        let html = page(article(source: nil))
        #expect(!html.contains("<base"))
        #expect(html.contains("<p class=\"grove-meta\"><span>Ada Lovelace</span><span>7 min read</span></p>"))
    }

    // MARK: - Page: escaping

    @Test func pageEscapesTitleInBothTitleAndHeading() {
        let html = page(article(title: "Cats & Dogs <script>alert(\"x\")</script>"))
        let escaped = "Cats &amp; Dogs &lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"
        #expect(html.contains("<title>\(escaped)</title>"))
        #expect(html.contains("<h1 class=\"grove-title\">\(escaped)</h1>"))
        #expect(!html.contains("<script>alert"))
    }

    @Test func pageEscapesBylineAndHost() {
        let html = page(article(byline: "\"Q\" & <A>", source: "https://a&b.example/post"))
        #expect(html.contains("<span>&quot;Q&quot; &amp; &lt;A&gt;</span>"))
        #expect(html.contains("<span>a&amp;b.example</span>"))
        #expect(html.contains("<base href=\"https://a&amp;b.example/post\">"))
    }

    @Test func pageEmbedsArticleContentVerbatim() {
        let content = "<p>One <em>two</em> &amp; <a href=\"/three\">three</a></p>"
        let html = page(article(content: content))
        #expect(html.contains("<div class=\"grove-content\">\n\(content)\n</div>"))
    }

    // MARK: - Page: meta line

    @Test func pageMetaListsBylineHostThenReadMinutes() {
        let html = page(article(), readMinutes: 12)
        #expect(html.contains(
            "<p class=\"grove-meta\"><span>Ada Lovelace</span><span>example.com</span><span>12 min read</span></p>"
        ))
    }

    @Test(arguments: [String?.none, "", ])
    func pageDropsAMissingOrEmptyByline(byline: String?) {
        let html = page(article(byline: byline))
        #expect(html.contains("<p class=\"grove-meta\"><span>example.com</span><span>7 min read</span></p>"))
    }

    @Test func pageUsesTheReadMinutesItIsGivenNotTheWordCount() {
        // 1,200 words would estimate 6 minutes; the caller's number wins.
        let html = page(article(wordCount: 1_200), readMinutes: 2)
        #expect(html.contains("<span>2 min read</span>"))
        #expect(!html.contains("6 min read"))
    }

    // MARK: - Page: fonts

    @Test func pageEmbedsTheSixGroveFacesAsDataURIs() {
        let html = page(article())
        #expect(occurrences(of: "@font-face", in: html) == 6)
        #expect(occurrences(of: "src: url(data:font/ttf;base64,", in: html) == 6)
        for family in ["'Newsreader'", "'IBM Plex Sans'", "'IBM Plex Mono'"] {
            #expect(html.contains("font-family: \(family);"), "missing \(family)")
        }
        #expect(html.contains("font-style: italic;"))
        #expect(html.contains("font-weight: 500;"))
    }

    @Test func pageFirstEmbeddedFaceIsTheBundledNewsreaderRegular() throws {
        let html = page(article())
        let base64 = try #require(slice(html, from: "src: url(data:font/ttf;base64,", to: ")"))
        let embedded = try #require(Data(base64Encoded: base64))
        let url = try #require(
            Bundle.main.url(forResource: "Newsreader-Regular", withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: "Newsreader-Regular", withExtension: "ttf")
        )
        #expect(embedded == (try Data(contentsOf: url)))
        // TrueType outlines start with 0x00010000.
        #expect(Array(embedded.prefix(4)) == [0x00, 0x01, 0x00, 0x00])
    }

    // MARK: - Page: typography

    @Test func pageAppliesTypographyAsRootVariables() {
        let typography = ReaderTypographySettings(sizeStep: 3, isWide: true, useSerif: false)
        let html = page(article(), typography: typography)
        #expect(html.contains("--reader-size: 23px;"))
        #expect(html.contains("--reader-measure: 80ch;"))
        #expect(html.contains("--reader-font: \(ReaderTemplate.sansStack);"))
    }

    @Test(arguments: [(-1, 16), (0, 16), (1, 18), (2, 20), (3, 23), (9, 23)])
    func typographySizeStepsClampToTheScale(step: Int, pixels: Int) {
        #expect(ReaderTypographySettings(sizeStep: step).fontSizePx == pixels)
    }

    @Test func typographyDefaultsMatchAFreshInstall() {
        let defaults = ReaderTypographySettings()
        #expect(defaults.sizeStep == ReaderTypographySettings.defaultSizeStep)
        #expect(defaults.measureCh == 66)
        #expect(defaults.bodyFontStack == ReaderTemplate.serifStack)
        #expect(ReaderTypographySettings(isWide: true).measureCh == 80)
        #expect(ReaderTypographySettings(useSerif: false).bodyFontStack == ReaderTemplate.sansStack)
    }

    @Test(arguments: [(0, 1), (1, 1), (230, 1), (231, 2), (460, 2), (461, 3), (2_300, 10)])
    func readMinutesRoundUpAt230WordsPerMinute(words: Int, minutes: Int) {
        #expect(article(wordCount: words).readMinutes == minutes)
    }

    // MARK: - JS string escaping

    @Test func escapeForJSStringEscapesQuotesBackslashesAndNewlines() {
        #expect(ReaderTemplate.escapeForJSString("it's") == #"it\'s"#)
        #expect(ReaderTemplate.escapeForJSString(#"a\b"#) == #"a\\b"#)
        #expect(ReaderTemplate.escapeForJSString("a\nb") == #"a\nb"#)
        #expect(ReaderTemplate.escapeForJSString("a\r\nb") == #"a\nb"#)
        // Backslashes go first, so an escaped quote is not escaped twice.
        #expect(ReaderTemplate.escapeForJSString(#"\'"#) == #"\\\'"#)
    }

    @Test(arguments: [
        "plain words",
        "it's a 'quoted' thing",
        #"C:\path\to\file"#,
        "trailing backslash \\",
        "line one\nline two",
        "windows\r\nline\r\nends",
        "</script><script>alert(1)</script>",
        "\"double\" and 'single'",
        "emoji 🌿 and accents é ñ",
        "separators \u{2028} and \u{2029}",
        "tab\tseparated",
    ])
    func escapeForJSStringRoundTripsThroughJavaScript(original: String) throws {
        let context = try #require(JSContext())
        let literal = "'" + ReaderTemplate.escapeForJSString(original) + "'"
        let value = context.evaluateScript(literal)
        #expect(context.exception == nil, "\(String(describing: context.exception))")
        // Carriage returns are dropped by design; everything else survives.
        #expect(value?.toString() == original.replacingOccurrences(of: "\r", with: ""))
    }

    // MARK: - Selection reporter

    @Test func selectionReporterPostsToTheNamedHandler() throws {
        let script = ReaderTemplate.selectionReporterJS(handler: "liveSelection")
        #expect(script.contains("var HANDLER = 'liveSelection';"))

        let harness = try ReaderJSHarness()
        try harness.installMessageHandler("liveSelection")
        try harness.run(script)
        try harness.setSelection("words", rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        try harness.dispatch("mouseup")
        try harness.flushTimers()
        #expect(try harness.messages(for: "liveSelection").count == 1)
    }

    @Test func selectionReporterPayloadDecodesToTextAndGeometry() throws {
        let harness = try ReaderJSHarness()
        try harness.installMessageHandler("selectionChanged")
        try harness.run(ReaderTemplate.selectionReporterJS(handler: "selectionChanged"))

        try harness.setSelection("  picked text \n", rect: CGRect(x: 10, y: 20, width: 30, height: 40))
        // mouseup, keyup and selectionchange share one debounce.
        try harness.dispatch("selectionchange")
        try harness.dispatch("mouseup")
        try harness.dispatch("keyup")
        try harness.flushTimers()

        let messages = try harness.messages(for: "selectionChanged")
        #expect(messages.count == 1)
        let decoded = WebSelectionGeometry.decode(try #require(messages.first))
        #expect(decoded.text == "picked text")
        #expect(decoded.geometry == WebSelectionGeometry(
            rect: CGRect(x: 10, y: 20, width: 30, height: 40),
            viewport: CGSize(width: 1024, height: 800)
        ))
    }

    @Test func selectionReporterSkipsRepeatsAndReReportsAfterScroll() throws {
        let harness = try ReaderJSHarness()
        try harness.installMessageHandler("selectionChanged")
        try harness.run(ReaderTemplate.selectionReporterJS(handler: "selectionChanged"))

        try harness.setSelection("same", rect: CGRect(x: 0, y: 300, width: 50, height: 18))
        try harness.dispatch("mouseup")
        try harness.flushTimers()
        try harness.dispatch("selectionchange")
        try harness.flushTimers()
        #expect(try harness.messages(for: "selectionChanged").count == 1)

        // Scrolling moves the selection; the new rect is re-reported.
        try harness.setSelection("same", rect: CGRect(x: 0, y: 120, width: 50, height: 18))
        try harness.dispatch("scroll", on: "window")
        try harness.flushTimers()
        let messages = try harness.messages(for: "selectionChanged")
        #expect(messages.count == 2)
        let moved = WebSelectionGeometry.decode(try #require(messages.last)).geometry
        #expect(moved?.rect.origin.y == 120)
    }

    @Test func selectionReporterSendsCollapsedSelectionWithoutGeometry() throws {
        let harness = try ReaderJSHarness()
        try harness.installMessageHandler("selectionChanged")
        try harness.run(ReaderTemplate.selectionReporterJS(handler: "selectionChanged"))
        try harness.setSelection("caret", rect: .zero)
        try harness.dispatch("mouseup")
        try harness.flushTimers()

        let decoded = WebSelectionGeometry.decode(try #require(try harness.messages(for: "selectionChanged").first))
        #expect(decoded.text == "caret")
        #expect(decoded.geometry == nil)
    }

    @Test func selectionReporterClearedSelectionDecodesToNothing() throws {
        let harness = try ReaderJSHarness()
        try harness.installMessageHandler("selectionChanged")
        try harness.run(ReaderTemplate.selectionReporterJS(handler: "selectionChanged"))

        try harness.setSelection("something", rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        try harness.dispatch("mouseup")
        try harness.flushTimers()
        try harness.setSelection(nil)
        try harness.dispatch("mouseup")
        try harness.flushTimers()

        let messages = try harness.messages(for: "selectionChanged")
        #expect(messages.count == 2)
        let cleared = WebSelectionGeometry.decode(try #require(messages.last))
        #expect(cleared.text == nil)
        #expect(cleared.geometry == nil)
    }

    @Test func selectionGeometryScalesIntoAPaneOfAnotherWidth() {
        let geometry = WebSelectionGeometry(
            rect: CGRect(x: 100, y: 50, width: 200, height: 20),
            viewport: CGSize(width: 800, height: 600)
        )
        #expect(geometry.rect(inPaneOfWidth: 400) == CGRect(x: 50, y: 25, width: 100, height: 10))
        #expect(geometry.rect(inPaneOfWidth: 0) == geometry.rect)
    }

    // MARK: - applyHighlightsJS

    @Test func applyHighlightsJSPassesStringsThroughIntact() throws {
        let highlights = ["it's \"quoted\"", "back\\slash", "two\nlines", "🌿 moss"]
        let animated = ["two\nlines"]
        let harness = try ReaderJSHarness()
        try harness.run("""
        window.__groveApplyHighlights = function(list, animated) {
            window.__received = { list: list, animated: animated };
            return list.length;
        };
        """)

        let result = try harness.run(ReaderTemplate.applyHighlightsJS(highlights, animated: animated))
        #expect(result.toInt32() == 4)
        #expect(try harness.run("__received.list").toArray() as? [String] == highlights)
        #expect(try harness.run("__received.animated").toArray() as? [String] == animated)
    }

    @Test func applyHighlightsJSIsANoOpBeforeTheMarkScriptLoads() throws {
        let harness = try ReaderJSHarness()
        let result = try harness.run(ReaderTemplate.applyHighlightsJS(["anything"], animated: []))
        #expect(result.isUndefined)
    }

    @Test func applyHighlightsJSWithNothingSendsEmptyArrays() {
        let js = ReaderTemplate.applyHighlightsJS([], animated: [])
        #expect(js.contains("window.__groveApplyHighlights([], [])"))
    }

    // MARK: - Live updates

    @Test(arguments: [true, false])
    func themeUpdateSetsTheThemeAttribute(isDark: Bool) throws {
        let harness = try ReaderJSHarness()
        try harness.run(ReaderTemplate.themeUpdateJS(isDark: isDark))
        let theme = try harness.run("document.documentElement.getAttribute('data-grove-theme')").toString()
        #expect(theme == (isDark ? "dark" : "light"))
    }

    @Test func typographyUpdateSetsTheThreeRootVariables() throws {
        let harness = try ReaderJSHarness()
        let typography = ReaderTypographySettings(sizeStep: 2, isWide: true, useSerif: false)
        try harness.run(ReaderTemplate.typographyUpdateJS(typography))
        let style = "document.documentElement.style"
        #expect(try harness.run("\(style)['--reader-size']").toString() == "20px")
        #expect(try harness.run("\(style)['--reader-measure']").toString() == "80ch")
        #expect(try harness.run("\(style)['--reader-font']").toString() == ReaderTemplate.sansStack)
    }

    @Test func typographyUpdateCarriesTheSerifStackIntact() throws {
        let harness = try ReaderJSHarness()
        try harness.run(ReaderTemplate.typographyUpdateJS(ReaderTypographySettings()))
        let font = try harness.run("document.documentElement.style['--reader-font']").toString()
        #expect(font == ReaderTemplate.serifStack)
    }

    // MARK: - Progress

    @Test func restoreProgressScrollsToTheFractionAndKeepsReapplying() throws {
        let harness = try ReaderJSHarness()
        try harness.run("document.documentElement.scrollHeight = 2400;")
        try harness.run(ReaderTemplate.restoreProgressJS(0.5))
        // 0.5 of (2400 - 800 viewport) = 800.
        #expect(try harness.run("JSON.stringify(window.__scrolls)").toString() == #"[{"left":0,"top":800}]"#)

        // Late images grow the page: the interval re-applies six more times.
        try harness.flushTimers()
        #expect(try harness.run("window.__scrolls.length").toInt32() == 7)
        try harness.dispatch("load", on: "window")
        #expect(try harness.run("window.__scrolls.length").toInt32() == 8)
    }

    @Test(arguments: ["wheel", "touchstart", "keydown", "mousedown"])
    func restoreProgressStopsOnceTheReaderTakesOver(event: String) throws {
        let harness = try ReaderJSHarness()
        try harness.run("document.documentElement.scrollHeight = 2400;")
        try harness.run(ReaderTemplate.restoreProgressJS(0.25))
        try harness.dispatch(event, on: "window")
        try harness.flushTimers()
        try harness.dispatch("load", on: "window")
        #expect(try harness.run("window.__scrolls.length").toInt32() == 1)
    }

    @Test func progressReporterPostsAThrottledFraction() throws {
        let harness = try ReaderJSHarness()
        try harness.installMessageHandler("readingProgress")
        try harness.run("document.documentElement.scrollHeight = 2800;")
        try harness.run(ReaderTemplate.progressReporterJS)

        try harness.run("window.scrollY = 500;")
        try harness.dispatch("scroll", on: "window")
        try harness.dispatch("scroll", on: "window")
        try harness.flushTimers()
        // 500 of (2800 - 800) scrollable.
        #expect(try harness.messages(for: "readingProgress") as? [Double] == [0.25])

        // Under half a percent of movement is not worth a message.
        try harness.run("window.scrollY = 505;")
        try harness.dispatch("scroll", on: "window")
        try harness.flushTimers()
        #expect(try harness.messages(for: "readingProgress").count == 1)

        try harness.run("window.scrollY = 5000;")
        try harness.dispatch("pagehide", on: "window")
        #expect(try harness.messages(for: "readingProgress") as? [Double] == [0.25, 1])
    }

    // MARK: - Load gating (ReaderModeSupport)

    @Test(arguments: [
        (0.0, nil), (0.01, nil), (0.0101, 0.0101), (0.5, 0.5), (0.9899, 0.9899), (0.99, nil), (1.0, nil),
    ] as [(Double, Double?)])
    func onlyMidArticleProgressIsRestored(fraction: Double, restored: Double?) {
        #expect(ReaderModeSupport.restorableProgress(fraction) == restored)
    }

    @Test func articleKeyChangesWithEachExtraction() {
        let first = article()
        var reExtracted = first
        reExtracted.extractedAt = first.extractedAt.addingTimeInterval(1)
        var restyled = first
        restyled.title = "Renamed"

        #expect(ReaderModeSupport.articleKey(first) == "https://example.com/essays/moss?ref=feed&utm=1#1700000000.0")
        #expect(ReaderModeSupport.articleKey(reExtracted) != ReaderModeSupport.articleKey(first))
        #expect(ReaderModeSupport.articleKey(restyled) == ReaderModeSupport.articleKey(first))
        #expect(ReaderModeSupport.articleKey(article(source: nil)) == "#1700000000.0")
    }

    // MARK: - Every injected script is valid JavaScript

    enum InjectedScript: String, CaseIterable, Sendable {
        case selectionReporter, syntaxHighlight, highlightMarks, progressReporter, scrollToText

        var source: String {
            switch self {
            case .selectionReporter: ReaderTemplate.selectionReporterJS(handler: "selectionChanged")
            case .syntaxHighlight: ReaderTemplate.syntaxHighlightJS
            case .highlightMarks: ReaderTemplate.highlightMarksJS
            case .progressReporter: ReaderTemplate.progressReporterJS
            case .scrollToText: ReaderTemplate.scrollToTextJS
            }
        }
    }

    /// The scripts live in Swift string literals, where one wrong escape
    /// turns a regex into a syntax error that WebKit reports nowhere.
    @Test(arguments: InjectedScript.allCases)
    func injectedScriptEvaluatesCleanly(script: InjectedScript) throws {
        let harness = try ReaderJSHarness(body: "<div class=\"grove-content\"><p>Body</p></div>")
        try harness.run(script.source)
    }

    @Test func injectedScriptsInstallTheirEntryPoints() throws {
        let harness = try ReaderJSHarness()
        try harness.run(ReaderTemplate.syntaxHighlightJS)
        try harness.run(ReaderTemplate.highlightMarksJS)
        try harness.run(ReaderTemplate.scrollToTextJS)
        for name in ["__groveHighlightCode", "__groveApplyHighlights", "__groveScrollToText"] {
            #expect(try harness.run("typeof window.\(name)").toString() == "function", "\(name)")
        }
    }
}
