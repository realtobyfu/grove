import Foundation
import SwiftData
import Testing
@testable import grove

/// How a stored highlight finds its way back onto rendered Reader content:
/// which quotes the panel hands over, which pass re-injects them, and the
/// in-page scripts that mark (`highlightMarksJS`) and jump to
/// (`scrollToTextJS`) the text — run in JavaScriptCore against a stand-in DOM.
struct ReaderHighlightTests {

    private func markHarness(_ body: String) throws -> ReaderJSHarness {
        let harness = try ReaderJSHarness(body: body)
        try harness.run(ReaderTemplate.highlightMarksJS)
        return harness
    }

    @discardableResult
    private func apply(_ highlights: [String], animated: [String] = [], in harness: ReaderJSHarness) throws -> Int {
        Int(try harness.call("__groveApplyHighlights", [highlights, animated]).toInt32())
    }

    private func scrollHarness(_ body: String) throws -> ReaderJSHarness {
        let harness = try ReaderJSHarness(body: body)
        try harness.run(ReaderTemplate.scrollToTextJS)
        return harness
    }

    private func scroll(to query: String, in harness: ReaderJSHarness) throws -> Bool {
        try harness.call("__groveScrollToText", [query]).toBool()
    }

    private let mark = #"<mark class="grove-highlight">"#

    // MARK: - Marking: matching

    @Test func exactQuoteIsWrappedInAMark() throws {
        let harness = try markHarness("<p>The quick brown fox jumps.</p>")
        #expect(try apply(["quick brown"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>The \(mark)quick brown</mark> fox jumps.</p>")
    }

    @Test func matchingIgnoresCase() throws {
        let harness = try markHarness("<p>The quick brown fox jumps.</p>")
        #expect(try apply(["QUICK Brown"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>The \(mark)quick brown</mark> fox jumps.</p>")
    }

    @Test func matchingSurvivesCollapsedWhitespace() throws {
        let harness = try markHarness("<p>The   quick\n    brown fox</p>")
        #expect(try apply(["quick brown"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>The   \(mark)quick\n    brown</mark> fox</p>")
    }

    @Test func matchingSurvivesWhitespaceAddedBySelection() throws {
        // A selection's toString() carries tabs and runs of spaces the DOM may not.
        let harness = try markHarness("<p>The quick brown fox</p>")
        #expect(try apply(["quick \t  brown\n"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>The \(mark)quick brown</mark> fox</p>")
    }

    @Test func quoteSelectedAcrossAParagraphBreakMarksBothBlocks() throws {
        // Selection text has "\n\n" where the concatenated DOM text has nothing.
        let harness = try markHarness("<p>End of one.</p><p>Start of two.</p>")
        #expect(try apply(["of one.\n\nStart"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>End \(mark)of one.</mark></p><p>\(mark)Start</mark> of two.</p>")
    }

    @Test func quoteSpanningInlineMarkupIsMarkedSegmentBySegment() throws {
        let body = #"<p>Read <a href="/x">the <em>whole</em> thing</a> now.</p>"#
        let harness = try markHarness(body)
        let textBefore = try harness.bodyText
        #expect(try apply(["the whole thing"], in: harness) == 1)
        #expect(try harness.bodyHTML ==
            #"<p>Read <a href="/x"><mark class="grove-highlight">the </mark><em><mark class="grove-highlight">whole</mark></em><mark class="grove-highlight"> thing</mark></a> now.</p>"#)
        #expect(try harness.bodyText == textBefore)
    }

    @Test func onlyTheFirstOccurrenceIsMarked() throws {
        let harness = try markHarness("<p>echo one, echo two</p>")
        #expect(try apply(["echo"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>\(mark)echo</mark> one, echo two</p>")
    }

    @Test func scriptAndStyleTextIsNeverMarked() throws {
        let body = #"<style>.needle { color: red; }</style><script>var s = "needle";</script><p>a needle here</p>"#
        let harness = try markHarness(body)
        #expect(try apply(["needle"], in: harness) == 1)
        #expect(try harness.bodyHTML ==
            #"<style>.needle { color: red; }</style><script>var s = "needle";</script><p>a <mark class="grove-highlight">needle</mark> here</p>"#)
    }

    // MARK: - Marking: no match

    @Test func quoteThatNoLongerMatchesLeavesThePageUntouched() throws {
        let body = "<p>The quick brown fox jumps.</p>"
        let harness = try markHarness(body)
        #expect(try apply(["slow green turtle"], in: harness) == 0)
        #expect(try harness.bodyHTML == body)
    }

    @Test func driftedQuoteIsSkippedWhileOthersStillApply() throws {
        let harness = try markHarness("<p>The quick brown fox jumps.</p>")
        #expect(try apply(["edited away", "fox"], in: harness) == 1)
        #expect(try harness.bodyHTML == "<p>The quick brown \(mark)fox</mark> jumps.</p>")
    }

    @Test func emptyAndWhitespaceOnlyQuotesAreSkipped() throws {
        let body = "<p>Some text.</p>"
        let harness = try markHarness(body)
        #expect(try apply(["", "   \n\t"], in: harness) == 0)
        #expect(try harness.bodyHTML == body)
    }

    @Test func anEmptyPageMarksNothing() throws {
        let harness = try markHarness("")
        #expect(try apply(["anything"], in: harness) == 0)
    }

    // MARK: - Marking: re-application

    @Test func reapplyingReplacesThePreviousMarks() throws {
        let body = "<p>The quick brown fox jumps.</p>"
        let harness = try markHarness(body)
        try apply(["quick"], in: harness)
        try apply(["fox"], in: harness)
        #expect(try harness.bodyHTML == "<p>The quick brown \(mark)fox</mark> jumps.</p>")

        // Clearing restores the original document, text nodes merged back.
        #expect(try apply([], in: harness) == 0)
        #expect(try harness.bodyHTML == body)
        #expect(try harness.run("document.body.firstChild.childNodes.length").toInt32() == 1)
    }

    @Test func newHighlightInksInOnceAndOldOnesDoNot() throws {
        let harness = try markHarness("<p>The quick brown fox jumps.</p>")
        #expect(try apply(["quick", "fox"], animated: ["fox"], in: harness) == 2)
        #expect(try harness.bodyHTML ==
            #"<p>The <mark class="grove-highlight">quick</mark> brown <mark class="grove-highlight grove-highlight--new">fox</mark> jumps.</p>"#)

        // The one-shot class is dropped after the keyframe.
        try harness.flushTimers()
        #expect(try harness.bodyHTML == "<p>The \(mark)quick</mark> brown \(mark)fox</mark> jumps.</p>")
    }

    @Test func swiftEmittedCallMarksQuotesWithQuotesAndNewlines() throws {
        let harness = try markHarness(#"<p>She said "it's here" and left.</p><p>Next line.</p>"#)
        let js = ReaderTemplate.applyHighlightsJS(["\"it's here\"", "left.\nNext"], animated: [])
        #expect(try harness.run(js).toInt32() == 2)
        #expect(try harness.bodyHTML ==
            #"<p>She said <mark class="grove-highlight">"it's here"</mark> and <mark class="grove-highlight">left.</mark></p><p><mark class="grove-highlight">Next</mark> line.</p>"#)
    }

    @Test func duplicateQuotesShareOneMark() throws {
        // Two reflections quoting the same passage.
        let harness = try markHarness("<p>The same words, then the same words.</p>")
        try apply(["same words", "same words"], in: harness)
        let markCount = try harness.run("document.querySelectorAll('mark.grove-highlight').length").toInt32()
        withKnownIssue("Each duplicate re-wraps the first occurrence, nesting marks and doubling the wash") {
            #expect(markCount == 1)
        }
    }

    // MARK: - Marking after syntax highlighting

    @Test func quoteInsideTokenizedCodeIsStillFound() throws {
        let body = #"<div class="grove-content"><pre><code class="language-swift">let total = 42 // answer</code></pre></div>"#
        let harness = try ReaderJSHarness(body: body)
        let textBefore = try harness.bodyText
        // Same order as the web view: tokenize first, then mark.
        try harness.run(ReaderTemplate.syntaxHighlightJS)
        try harness.run(ReaderTemplate.highlightMarksJS)
        #expect(try harness.bodyText == textBefore)

        #expect(try apply(["total = 42"], in: harness) == 1)
        #expect(try harness.bodyText == textBefore)
        let marked = try harness.run("Array.prototype.map.call(document.querySelectorAll('mark.grove-highlight'), function(m) { return m.textContent; }).join('|')").toString()
        #expect(marked == "total = |42")
    }

    // MARK: - Syntax highlighting keeps the text

    @Test func syntaxHighlightTokenizesHintedBlocksWithoutChangingTheirText() throws {
        let body = #"<div class="grove-content"><pre><code class="language-swift">let x = 1 // note &lt;b&gt;</code></pre></div>"#
        let harness = try ReaderJSHarness(body: body)
        let textBefore = try harness.bodyText
        try harness.run(ReaderTemplate.syntaxHighlightJS)
        #expect(try harness.bodyHTML ==
            #"<div class="grove-content"><pre><code class="language-swift" data-grove-hl="swift"><span class="gtok-kw">let</span> x = <span class="gtok-num">1</span> <span class="gtok-com">// note &lt;b&gt;</span></code></pre></div>"#)
        #expect(try harness.bodyText == textBefore)
    }

    @Test(arguments: [
        #"<div class="grove-content"><pre>Just some prose in a box.</pre></div>"#,
        #"<div class="grove-content"><pre><code class="language-text">let x = 1;</code></pre></div>"#,
        #"<div class="grove-content"><p>Inline <code>let x = 1</code> stays plain.</p></div>"#,
        #"<section><pre><code class="language-swift">let x = 1</code></pre></section>"#,
    ])
    func syntaxHighlightLeavesNonCodeAndOutsideBlocksAlone(body: String) throws {
        let harness = try ReaderJSHarness(body: body)
        try harness.run(ReaderTemplate.syntaxHighlightJS)
        #expect(try harness.bodyHTML == body)
    }

    @Test func syntaxHighlightRunsOncePerBlock() throws {
        let body = #"<div class="grove-content"><pre><code class="language-python">def f(): return None</code></pre></div>"#
        let harness = try ReaderJSHarness(body: body)
        try harness.run(ReaderTemplate.syntaxHighlightJS)
        let once = try harness.bodyHTML
        try harness.run("window.__groveHighlightCode();")
        #expect(try harness.bodyHTML == once)
        #expect(once.contains(#"data-grove-hl="py""#))
    }

    @Test(arguments: [
        ("{\n  \"name\": \"grove\",\n  \"version\": 2\n}", "json"),
        ("import SwiftUI\nstruct A: View { var body: some View { Text(\"x\") } }", "swift"),
        ("package main\nfunc main() { x := 1 }", "go"),
        ("SELECT id FROM items WHERE id = 1;", "sql"),
    ])
    func syntaxHighlightDetectsUnhintedLanguages(code: String, language: String) throws {
        let harness = try ReaderJSHarness()
        harness.set("__code", code)
        try harness.run("""
        var pre = document.createElement('pre');
        pre.appendChild(document.createTextNode(__code));
        var content = document.createElement('div');
        content.className = 'grove-content';
        content.appendChild(pre);
        document.body.appendChild(content);
        """)
        try harness.run(ReaderTemplate.syntaxHighlightJS)
        #expect(try harness.run("document.querySelector('pre').getAttribute('data-grove-hl')").toString() == language)
        #expect(try harness.run("document.querySelector('pre').textContent").toString() == code)
    }

    // MARK: - Scroll to text

    @Test func scrollToTextFindsTheQuoteAndScrollsItNearTheTop() throws {
        let harness = try scrollHarness("<p>Alpha beta gamma</p>")
        #expect(try scroll(to: "beta", in: harness))
        // Range rect top 400 lands at 30% of an 800pt viewport: 400 - 240.
        #expect(try harness.run("JSON.stringify(window.__scrolls)").toString() == #"[{"top":160,"behavior":"smooth"}]"#)
        #expect(try harness.run("window.__lastRange.toString()").toString() == "beta")
    }

    @Test func scrollToTextIgnoresCaseAndReturnsTheDocumentText() throws {
        let harness = try scrollHarness("<p>Alpha Beta Gamma</p>")
        #expect(try scroll(to: "bEtA gAm", in: harness))
        #expect(try harness.run("window.__lastRange.toString()").toString() == "Beta Gam")
    }

    @Test func scrollToTextSpansInlineMarkup() throws {
        let harness = try scrollHarness(#"<p>Read <a href="/x">the <em>whole</em> thing</a> now.</p>"#)
        #expect(try scroll(to: "hole thing", in: harness))
        #expect(try harness.run("window.__lastRange.toString()").toString() == "hole thing")
        #expect(try harness.run("window.__lastRange.startContainer.parentElement.tagName").toString() == "EM")
        #expect(try harness.run("window.__lastRange.endContainer.parentElement.tagName").toString() == "A")
    }

    @Test func scrollToTextSkipsScriptAndStyleText() throws {
        let harness = try scrollHarness(#"<script>var a = "quoted line";</script><p>quoted line</p>"#)
        #expect(try scroll(to: "quoted line", in: harness))
        #expect(try harness.run("window.__lastRange.startContainer.parentElement.tagName").toString() == "P")
    }

    @Test(arguments: ["", "not on the page"])
    func scrollToTextReportsAMissAndDoesNotScroll(query: String) throws {
        let harness = try scrollHarness("<p>Alpha beta gamma</p>")
        #expect(try !scroll(to: query, in: harness))
        #expect(try harness.run("window.__scrolls.length").toInt32() == 0)
    }

    @Test func scrollToTextFlashesAMarkerThatRemovesItself() throws {
        let harness = try scrollHarness("<p>Alpha beta gamma</p>")
        #expect(try scroll(to: "gamma", in: harness))
        let marker = "document.body.lastChild"
        #expect(try harness.run("\(marker).tagName").toString() == "DIV")
        #expect(try harness.run("\(marker).style.top").toString() == "399px")
        #expect(try harness.run("\(marker).style.left").toString() == "22px")
        #expect(try harness.run("\(marker).style.width").toString() == "124px")
        #expect(try harness.run("\(marker).style.height").toString() == "22px")

        try harness.flushTimers()
        #expect(try harness.bodyHTML == "<p>Alpha beta gamma</p>")
    }

    @Test func swiftEscapedScrollCallFindsQuotesWithApostrophesAndBackslashes() throws {
        let quote = #"it's "here" \ now"#
        let harness = try scrollHarness(#"<p>Look: it's "here" \ now.</p>"#)
        // The exact call ReaderModeSupport and the coordinator emit.
        let call = "window.__groveScrollToText('\(ReaderTemplate.escapeForJSString(quote))');"
        #expect(try harness.run(call).toBool())
        #expect(try harness.run("window.__lastRange.toString()").toString() == quote)
    }

    @Test func scrollToTextFindsAQuoteSelectedAcrossAParagraphBreak() throws {
        // jumpToHighlight sends the stored quote, which keeps the "\n\n" the
        // selection carried; the marks script tolerates that, this one does not.
        let harness = try scrollHarness("<p>End of one.</p><p>Start of two.</p>")
        let found = try scroll(to: "of one.\n\nStart", in: harness)
        withKnownIssue("scrollToTextJS matches exactly, so a multi-paragraph highlight can be marked but not jumped to") {
            #expect(found)
        }
    }

    // MARK: - Highlight passes (ReaderModeSupport)

    @Test func firstPassAfterALoadAnimatesNothing() {
        let pass = ReaderModeSupport.highlightPass(desired: ["a", "b"], previous: nil)
        #expect(pass?.highlights == ["a", "b"])
        #expect(pass?.animated == [])
    }

    @Test func firstPassOnAPageWithNoHighlightsStillClears() {
        // A fresh document has nothing to clear, but the pass is what records
        // the set as applied, so it must still run.
        let pass = ReaderModeSupport.highlightPass(desired: [], previous: nil)
        #expect(pass?.highlights == [])
    }

    @Test func unchangedSetIsNotReinjected() {
        #expect(ReaderModeSupport.highlightPass(desired: ["a", "b"], previous: ["a", "b"])?.highlights == nil)
        #expect(ReaderModeSupport.highlightPass(desired: [], previous: [])?.highlights == nil)
    }

    @Test func onlyNewQuotesInkIn() {
        let pass = ReaderModeSupport.highlightPass(desired: ["a", "b", "c"], previous: ["a", "c"])
        #expect(pass?.highlights == ["a", "b", "c"])
        #expect(pass?.animated == ["b"])
    }

    @Test func deletingAQuoteReinjectsTheRestWithoutAnimation() {
        let pass = ReaderModeSupport.highlightPass(desired: ["a"], previous: ["a", "b"])
        #expect(pass?.highlights == ["a"])
        #expect(pass?.animated == [])
    }

    @Test func reorderingReinjectsWithoutAnimation() {
        let pass = ReaderModeSupport.highlightPass(desired: ["b", "a"], previous: ["a", "b"])
        #expect(pass?.animated == [])
    }

    // MARK: - Which quotes a page gets

    @MainActor
    @Test func pageQuotesFollowReflectionOrderTrimmedWithEmptiesDropped() throws {
        let context = try makeInMemoryModelContext()
        let item = Item(title: "Moss", type: .article)
        context.insert(item)
        let blocks = [
            ReflectionBlock(item: item, blockType: .keyInsight, highlight: "  third quote\n", position: 2),
            ReflectionBlock(item: item, blockType: .keyInsight, highlight: nil, position: 0),
            ReflectionBlock(item: item, blockType: .keyInsight, highlight: "first quote", position: 1),
            ReflectionBlock(item: item, blockType: .keyInsight, highlight: " \n\t ", position: 3),
        ]
        for block in blocks { context.insert(block) }

        #expect(ItemReaderWebViewPanel.highlightQuotes(from: blocks) == ["first quote", "third quote"])
        #expect(ItemReaderWebViewPanel.highlightQuotes(from: []) == [])
    }

    @MainActor
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "ReaderHighlightTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
