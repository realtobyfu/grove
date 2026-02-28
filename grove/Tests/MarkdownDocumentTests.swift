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

    @available(macOS 26, *)
    @Test func attributedStringConverterRoundTripsMarkdownSource() {
        let source = """
        # Heading

        >quote

        - item

        Here is *italic*, **bold**, and [[Link]].
        """

        let converter = MarkdownAttributedStringConverter()
        let attributed = converter.attributedString(from: source)

        #expect(converter.markdown(from: attributed) == source)
    }

    @Test func appearanceSettingsDefaultMarkdownEditorModeDefaultsAndPersists() {
        let defaults = UserDefaults.standard
        let key = "grove.appearance.defaultMarkdownEditorMode"
        let originalValue = defaults.string(forKey: key)

        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        #expect(AppearanceSettings.defaultMarkdownEditorMode == .livePreview)

        AppearanceSettings.defaultMarkdownEditorMode = .source
        #expect(AppearanceSettings.defaultMarkdownEditorMode == .source)
        #expect(defaults.string(forKey: key) == MarkdownEditorMode.source.rawValue)
    }
}
