import Foundation
import Testing
@testable import grove

struct MarkdownDocumentTests {
    @Test func blockquoteParsingAcceptsTightAndSpacedPrefixes() {
        let tightDocument = MarkdownDocument(">quote")
        let spacedDocument = MarkdownDocument("> quote")

        #expect(tightDocument.source == ">quote")
        #expect(spacedDocument.source == "> quote")
        #expect(tightDocument.blocks.count == 1)
        #expect(spacedDocument.blocks.count == 1)

        guard case .blockquote(let tightQuote) = tightDocument.blocks.first?.kind else {
            Issue.record("Expected tight blockquote")
            return
        }
        guard case .blockquote(let spacedQuote) = spacedDocument.blocks.first?.kind else {
            Issue.record("Expected spaced blockquote")
            return
        }

        #expect(tightQuote.lines.count == 1)
        #expect(spacedQuote.lines.count == 1)
        #expect(tightDocument.text(in: tightQuote.lines[0].contentRange) == "quote")
        #expect(spacedDocument.text(in: spacedQuote.lines[0].contentRange) == "quote")
        #expect(tightQuote.lines[0].prefixRange == 0..<1)
        #expect(spacedQuote.lines[0].prefixRange == 0..<2)
    }

    @Test func inlinePresentationRemovesMarkersAndKeepsSemanticSpans() {
        let source = "This is *italic* and **bold** plus [[Note]] and [site](https://example.com)."
        let document = MarkdownDocument(source)
        let presentation = document.inlinePresentation(in: 0..<source.count)

        #expect(presentation.text == "This is italic and bold plus Note and site.")
        #expect(presentation.spans.count == 4)

        let kinds = presentation.spans.map(\.kind)

        #expect(kinds.contains { kind in
            if case .italic = kind { return true }
            return false
        })
        #expect(kinds.contains { kind in
            if case .bold = kind { return true }
            return false
        })
        #expect(kinds.contains { kind in
            if case .wikiLink(let title) = kind { return title == "Note" }
            return false
        })
        #expect(kinds.contains { kind in
            if case .link(let url) = kind { return url == "https://example.com" }
            return false
        })
    }

    @Test func inlineRevealRulesFollowCaretAndSelection() {
        let source = "A **bold** and *italic* example."
        let document = MarkdownDocument(source)
        let spans = document.inlineSpans

        guard let boldSpan = spans.first(where: {
            if case .bold = $0.kind { return true }
            return false
        }) else {
            Issue.record("Expected bold span")
            return
        }

        guard let italicSpan = spans.first(where: {
            if case .italic = $0.kind { return true }
            return false
        }) else {
            Issue.record("Expected italic span")
            return
        }

        #expect(!document.shouldRevealInlineSpan(boldSpan, for: .init(caret: 0)))
        #expect(document.shouldRevealInlineSpan(boldSpan, for: .init(caret: boldSpan.fullRange.lowerBound)))
        #expect(document.shouldRevealInlineSpan(boldSpan, for: .init(caret: boldSpan.contentRange.lowerBound + 1)))
        #expect(document.shouldRevealInlineSpan(boldSpan, for: .init(caret: boldSpan.fullRange.upperBound)))
        #expect(document.shouldRevealInlineSpan(italicSpan, for: .init(range: italicSpan.contentRange.lowerBound..<(italicSpan.contentRange.lowerBound + 2))))
    }

    @Test func boldItalicRevealKeepsTripleMarkersEditableWhenActive() {
        let source = "***text***"
        let document = MarkdownDocument(source)

        guard let span = document.inlineSpans.first else {
            Issue.record("Expected bold-italic span")
            return
        }

        #expect(!document.shouldRevealInlineSpan(span, for: .init(caret: source.count + 1)))
        #expect(document.shouldRevealInlineSpan(span, for: .init(caret: span.contentRange.lowerBound + 1)))
        #expect(span.markerRanges.count == 2)
        #expect(document.text(in: span.markerRanges[0]) == "***")
        #expect(document.text(in: span.markerRanges[1]) == "***")
    }

    @Test func headingAndPrefixRevealRulesMatchInlineEditingBehavior() {
        let source = """
        # Heading
        > Quote
        - Item
        """
        let document = MarkdownDocument(source)

        guard case .heading(let heading) = document.blocks[0].kind else {
            Issue.record("Expected heading block")
            return
        }
        guard case .blockquote(let quote) = document.blocks[1].kind else {
            Issue.record("Expected blockquote block")
            return
        }
        guard case .bulletList(let list) = document.blocks[2].kind else {
            Issue.record("Expected list block")
            return
        }

        #expect(document.shouldRevealHeading(heading, for: .init(caret: heading.contentRange.lowerBound)))
        #expect(!document.shouldRevealHeading(heading, for: .init(caret: quote.lines[0].contentRange.lowerBound)))

        let quotePrefix = quote.lines[0].prefixRange
        let listPrefix = list.items[0].prefixRange
        #expect(!document.shouldRevealPrefix(quotePrefix, for: .init(caret: quote.lines[0].contentRange.lowerBound)))
        #expect(document.shouldRevealPrefix(quotePrefix, for: .init(caret: quotePrefix.lowerBound)))
        #expect(!document.shouldRevealPrefix(listPrefix, for: .init(caret: list.items[0].contentRange.lowerBound)))
        #expect(document.shouldRevealPrefix(listPrefix, for: .init(caret: listPrefix.upperBound - 1)))
    }

    @Test func linkRevealRulesOnlyActivateForTheFocusedLinkSpan() {
        let source = "[site](https://example.com) and [[Note]]"
        let document = MarkdownDocument(source)
        let spans = document.inlineSpans

        guard let markdownLink = spans.first(where: {
            if case .link = $0.kind { return true }
            return false
        }) else {
            Issue.record("Expected markdown link span")
            return
        }

        guard let wikiLink = spans.first(where: {
            if case .wikiLink = $0.kind { return true }
            return false
        }) else {
            Issue.record("Expected wiki link span")
            return
        }

        #expect(document.shouldRevealInlineSpan(markdownLink, for: .init(caret: markdownLink.contentRange.lowerBound)))
        #expect(!document.shouldRevealInlineSpan(wikiLink, for: .init(caret: markdownLink.contentRange.lowerBound)))
        #expect(document.shouldRevealInlineSpan(wikiLink, for: .init(caret: wikiLink.fullRange.upperBound)))
        #expect(!document.shouldRevealInlineSpan(markdownLink, for: .init(caret: wikiLink.contentRange.lowerBound)))
    }

    @Test func codeFenceRevealTracksFenceLineSelection() {
        let source = """
        ```swift
        print("hello")
        ```
        """
        let document = MarkdownDocument(source)

        guard case .codeBlock(let codeBlock) = document.blocks.first?.kind else {
            Issue.record("Expected code block")
            return
        }

        #expect(document.shouldRevealCodeFence(codeBlock.openingFenceRange, for: .init(caret: codeBlock.openingFenceRange.lowerBound)))
        #expect(!document.shouldRevealCodeFence(codeBlock.openingFenceRange, for: .init(caret: codeBlock.contentRange?.lowerBound ?? 0)))
        if let closingFenceRange = codeBlock.closingFenceRange {
            #expect(document.shouldRevealCodeFence(closingFenceRange, for: .init(caret: closingFenceRange.upperBound)))
        } else {
            Issue.record("Expected closing fence range")
        }
    }
}
