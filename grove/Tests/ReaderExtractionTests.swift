import Foundation
import JavaScriptCore
import SwiftData
import Testing
@testable import grove

/// Fetched page → `ReadableArticle`. Readability.js itself needs a full DOM,
/// so these cover what Grove owns around it: the wrapper script run in the
/// page (against a stub `Readability` in JavaScriptCore), the bundled
/// library's failure path, and the Swift side that validates the JSON result.
struct ReaderExtractionTests {

    // MARK: - Fixtures

    private static let source = URL(string: "https://example.com/blog/moss-field-guide")!
    private static let extractedAt = Date(timeIntervalSince1970: 1_750_000_000)

    /// `count` words of article text, comfortably past the length floor when
    /// `count` is a hundred or more.
    private func prose(words count: Int) -> String {
        (1...count).map { "word\($0)" }.joined(separator: " ")
    }

    private func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func article(fromJSON json: String?, sourceURL: URL? = source) -> ReadableArticle? {
        ArticleReaderService.article(fromExtractionResult: json, sourceURL: sourceURL, extractedAt: Self.extractedAt)
    }

    /// A Readability stand-in: refuses anything but a deep clone of the page
    /// and returns whatever `__parseResult` holds.
    private static let stubReadability = """
    function Readability(doc) {
        if (!doc || doc.__isDeepClone !== true) { throw new Error('expected a deep clone of the document'); }
        this._doc = doc;
    }
    Readability.prototype.parse = function() { return globalThis.__parseResult; };
    """

    /// Runs the extraction wrapper in a fresh context and returns what it
    /// hands back to Swift (nil for JS `null`).
    private func runExtractionScript(
        readability: String = stubReadability,
        document: String = "{ cloneNode: function(deep) { return { __isDeepClone: deep === true }; } }",
        parseResult: String = "null"
    ) throws -> (result: String?, context: JSContext) {
        let context = try #require(JSContext())
        context.evaluateScript("var document = \(document); var __parseResult = \(parseResult);")
        let value = context.evaluateScript(ArticleReaderService.extractionScript(readability: readability))
        #expect(context.exception == nil, "\(String(describing: context.exception))")
        let result = try #require(value)
        return (result.isNull || result.isUndefined ? nil : result.toString(), context)
    }

    // MARK: - Extraction script (stub Readability)

    @Test func scriptMarshalsReadabilityFieldsAsJSON() throws {
        let text = prose(words: 120)
        let (result, _) = try runExtractionScript(parseResult: """
        { title: '  A Field Guide to Moss  ', byline: '  Ada Lovelace ', content: '<p>Moss.</p>',
          textContent: '\(text)', length: 913, excerpt: 'Moss grows.', siteName: 'ignored' }
        """)

        let article = try #require(article(fromJSON: result))
        #expect(article.title == "A Field Guide to Moss")
        #expect(article.byline == "Ada Lovelace")
        #expect(article.contentHTML == "<p>Moss.</p>")
        #expect(article.textContent == text)
        #expect(article.length == 913)
        #expect(article.excerpt == "Moss grows.")
        #expect(article.wordCount == 120)
        #expect(article.sourceURLString == "https://example.com/blog/moss-field-guide")
        #expect(article.extractedAt == Self.extractedAt)
    }

    @Test func scriptHandsReadabilityADeepCloneNotTheLivePage() throws {
        // The stub throws unless it receives cloneNode(true)'s result, and a
        // throw comes back as null — so a non-nil result proves the clone.
        let (result, _) = try runExtractionScript(
            parseResult: "{ title: 't', content: '<p>x</p>', textContent: 'x' }"
        )
        #expect(result != nil)

        let (shallow, _) = try runExtractionScript(
            document: "{ cloneNode: function(deep) { return { __isDeepClone: false }; } }",
            parseResult: "{ title: 't', content: '<p>x</p>', textContent: 'x' }"
        )
        #expect(shallow == nil)
    }

    @Test(arguments: [
        "null",
        "undefined",
        "{ title: 'No body', textContent: 'text' }",
        "{ title: 'No text', content: '<p>x</p>' }",
        "{ title: 'Empty', content: '', textContent: '' }",
    ])
    func scriptReturnsNullWhenReadabilityFindsNothing(parseResult: String) throws {
        let (result, _) = try runExtractionScript(parseResult: parseResult)
        #expect(result == nil)
        #expect(article(fromJSON: result) == nil)
    }

    @Test func scriptSwallowsAReadabilityThrow() throws {
        let throwing = "function Readability() { throw new Error('boom'); }"
        let (result, _) = try runExtractionScript(readability: throwing)
        #expect(result == nil)
    }

    @Test func scriptLeavesNoGlobalsBehind() throws {
        let (_, context) = try runExtractionScript(
            parseResult: "{ title: 't', content: '<p>x</p>', textContent: 'x' }"
        )
        #expect(context.evaluateScript("typeof Readability")?.toString() == "undefined")
        #expect(context.evaluateScript("typeof article")?.toString() == "undefined")
    }

    // MARK: - Extraction script (bundled Readability.js)

    @Test func bundledReadabilityIsShippedAndDefinesTheConstructor() throws {
        let source = try #require(ArticleReaderService.readabilitySource)
        let context = try #require(JSContext())
        context.evaluateScript(source)
        #expect(context.exception == nil, "\(String(describing: context.exception))")
        #expect(context.evaluateScript("typeof Readability")?.toString() == "function")
        #expect(context.evaluateScript("typeof Readability.prototype.parse")?.toString() == "function")
    }

    @Test(arguments: [
        "{ cloneNode: function() { return {}; } }",            // no documentElement
        "{ cloneNode: function() { return null; } }",
        "{ cloneNode: function() { throw new Error('detached'); } }",
        "{}",                                                  // not a document at all
    ])
    func bundledReadabilityFailsGracefullyOnAGarbageDocument(document: String) throws {
        let readability = try #require(ArticleReaderService.readabilitySource)
        let (result, context) = try runExtractionScript(readability: readability, document: document)
        #expect(result == nil)
        #expect(article(fromJSON: result) == nil)
        #expect(context.evaluateScript("typeof Readability")?.toString() == "undefined")
    }

    // MARK: - JSON result → ReadableArticle

    @Test(arguments: [nil, "", "not json", "[]", "{}", #"{"content": "<p>x</p>"}"#, #"{"textContent": "x"}"#])
    func unusableResultsAreRejected(raw: String?) {
        #expect(article(fromJSON: raw) == nil)
    }

    @Test func textShorterThanTheFloorIsRejectedAfterTrimming() throws {
        let floor = ArticleReaderService.minimumExtractedLength
        #expect(floor == 500)
        let short = "\n\n   " + String(repeating: "a", count: floor - 1) + "   \n"
        let exact = "\n\n   " + String(repeating: "a", count: floor) + "   \n"
        #expect(article(fromJSON: try json(["content": "<p>x</p>", "textContent": short])) == nil)
        #expect(article(fromJSON: try json(["content": "<p>x</p>", "textContent": exact])) != nil)
    }

    @Test func missingLengthFallsBackToTheTrimmedTextLength() throws {
        let text = "  " + prose(words: 100) + "\n"
        let article = try #require(article(fromJSON: try json(["content": "<p>x</p>", "textContent": text])))
        #expect(article.length == text.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    @Test func wordCountSplitsOnAnyWhitespace() throws {
        let text = prose(words: 100) + "\nnewline\ttab  double\u{00A0}nbsp"
        let article = try #require(article(fromJSON: try json(["content": "<p>x</p>", "textContent": text])))
        #expect(article.wordCount == 104)
    }

    @Test func missingTitleAndBylineDegradeQuietly() throws {
        let article = try #require(article(
            fromJSON: try json(["content": "<p>x</p>", "textContent": prose(words: 100)]),
            sourceURL: nil
        ))
        #expect(article.title == "")
        #expect(article.byline == nil)
        #expect(article.excerpt == nil)
        #expect(article.sourceURLString == nil)
    }

    @Test func nullJSONFieldsAreTreatedAsMissing() throws {
        let raw = try json([
            "title": NSNull(), "byline": NSNull(), "content": "<p>x</p>",
            "textContent": prose(words: 100), "length": NSNull(), "excerpt": NSNull(),
        ])
        let article = try #require(article(fromJSON: raw))
        #expect(article.title == "")
        #expect(article.byline == nil)
    }

    // MARK: - Relative URLs

    /// Readability rewrites relative links against the page it ran in; what
    /// Grove adds is carrying that page's URL through to the reader page's
    /// `<base>`, so anything still relative resolves against the original site.
    @Test func extractedArticleCarriesItsPageURLToTheReaderBaseHref() throws {
        let raw = try json([
            "title": "Moss",
            "content": #"<p><img src="images/moss.jpg"><a href="../about">About</a></p>"#,
            "textContent": prose(words: 100),
        ])
        let article = try #require(article(fromJSON: raw))
        let html = ReaderTemplate.page(
            article: article,
            typography: ReaderTypographySettings(),
            isDark: false,
            readMinutes: article.readMinutes
        )
        #expect(html.contains(#"<base href="https://example.com/blog/moss-field-guide">"#))
        #expect(html.contains(#"<img src="images/moss.jpg">"#))
    }

    @Test func cachedArticleJSONRoundTripsThroughCodable() throws {
        let original = try #require(article(fromJSON: try json([
            "title": "Moss", "byline": "Ada", "content": "<p>x</p>",
            "textContent": prose(words: 100), "excerpt": "Short",
        ])))
        // Same strategy the disk cache uses.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ReadableArticle.self, from: try encoder.encode(original))
        #expect(decoded == original)
    }
}

/// The view-model state that decides which extraction Reader mode shows and
/// how reading position and jump requests reach the web views.
@MainActor
struct ReaderViewModelStateTests {

    private func makeViewModel(type: ItemType = .article) throws -> ItemReaderViewModel {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "ReaderViewModelStateTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let item = Item(title: "Moss", type: type)
        item.sourceURL = "https://example.com/moss"
        context.insert(item)
        return ItemReaderViewModel(item: item, modelContext: context)
    }

    private func readable(_ url: String) -> ReadableArticle {
        ReadableArticle(
            title: url, byline: nil, contentHTML: "<p>x</p>", textContent: "x", length: 1,
            excerpt: nil, sourceURLString: url, extractedAt: .distantPast, wordCount: 1
        )
    }

    // MARK: - Which article Reader shows

    @Test func ownPageShowsTheItemsArticle() throws {
        let vm = try makeViewModel()
        let own = readable("https://example.com/moss")
        vm.readerArticle = own
        #expect(vm.activeReaderArticle == own)
        #expect(!vm.isResolvingNavigatedArticle)
    }

    @Test func followedLinkShowsItsOwnExtractionNotTheItems() throws {
        let vm = try makeViewModel()
        vm.readerArticle = readable("https://example.com/moss")
        let linked = try #require(URL(string: "https://example.com/lichen"))
        vm.navigatedWebURL = linked
        vm.navigatedReaderArticle = readable(linked.absoluteString)
        vm.navigatedReaderArticleURL = linked
        #expect(vm.activeReaderArticle?.sourceURLString == "https://example.com/lichen")
        #expect(!vm.isResolvingNavigatedArticle)
    }

    @Test func staleExtractionForAnEarlierLinkIsNeverShown() throws {
        let vm = try makeViewModel()
        vm.readerArticle = readable("https://example.com/moss")
        let earlier = try #require(URL(string: "https://example.com/lichen"))
        vm.navigatedReaderArticle = readable(earlier.absoluteString)
        vm.navigatedReaderArticleURL = earlier
        vm.navigatedWebURL = try #require(URL(string: "https://example.com/fern"))
        #expect(vm.activeReaderArticle == nil)
    }

    @Test func followedLinkIsResolvingUntilItsExtractionIsAttempted() throws {
        let vm = try makeViewModel()
        let linked = try #require(URL(string: "https://example.com/lichen"))
        vm.navigatedWebURL = linked
        #expect(vm.isResolvingNavigatedArticle)
        #expect(vm.activeReaderArticle == nil)

        // Attempted and failed: the page has proved unreadable.
        vm.navigatedExtractionAttemptedURL = linked
        #expect(!vm.isResolvingNavigatedArticle)
    }

    @Test func videoItemsNeverResolveAReaderView() throws {
        let vm = try makeViewModel(type: .video)
        vm.navigatedWebURL = try #require(URL(string: "https://example.com/lichen"))
        #expect(vm.suppressesReaderMode)
        #expect(!vm.isResolvingNavigatedArticle)
    }

    // MARK: - Selection and jumps

    @Test func highlightableSelectionIsTrimmedAndNeverBlank() throws {
        let vm = try makeViewModel()
        vm.webSelectedText = "\n  a passage worth keeping \t"
        #expect(vm.highlightableSelection == "a passage worth keeping")
        vm.webSelectedText = " \n\t "
        #expect(vm.highlightableSelection == nil)
        vm.webSelectedText = nil
        #expect(vm.highlightableSelection == nil)
    }

    @Test func scrollToTextSendsTheTrimmedQuoteAndBumpsTheToken() throws {
        let vm = try makeViewModel()
        let token = vm.scrollToTextToken
        vm.scrollToText("  of one.\n\nStart  ")
        #expect(vm.scrollToTextQuery == "of one.\n\nStart")
        #expect(vm.scrollToTextToken == token + 1)

        vm.scrollToText(" \n ")
        #expect(vm.scrollToTextToken == token + 1)
    }

    // MARK: - Reading progress

    @Test func readingProgressPersistsOnlyMeaningfulMoves() throws {
        let vm = try makeViewModel()
        vm.updateReadingProgress(0.02)
        #expect(vm.item.metadata["readingProgress"] == "0.020")

        vm.updateReadingProgress(0.05)  // +0.03: live only
        #expect(vm.liveReadingProgress == 0.05)
        #expect(vm.item.metadata["readingProgress"] == "0.020")

        vm.updateReadingProgress(0.08)  // +0.06 from the last save
        #expect(vm.item.metadata["readingProgress"] == "0.080")
        #expect(vm.readingProgress == 0.08)
    }

    @Test func readingProgressAlwaysPersistsTheEndAndClamps() throws {
        let vm = try makeViewModel()
        vm.updateReadingProgress(0.996)
        vm.updateReadingProgress(0.997)  // tiny move, but at the end
        #expect(vm.item.metadata["readingProgress"] == "0.997")

        vm.updateReadingProgress(1.4)
        #expect(vm.item.metadata["readingProgress"] == "1.000")
        vm.updateReadingProgress(-0.2)
        #expect(vm.item.metadata["readingProgress"] == "0.000")
        #expect(vm.liveReadingProgress == 0)
    }
}
