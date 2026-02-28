#if os(macOS)
import SwiftUI

// MARK: - Custom Attributed String Keys

@available(macOS 26, *)
enum BoldAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveBold"
    static let inheritedByAddedText = true
}

@available(macOS 26, *)
enum ItalicAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveItalic"
    static let inheritedByAddedText = true
}

@available(macOS 26, *)
enum InlineCodeAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveInlineCode"
    static let inheritedByAddedText = false
}

@available(macOS 26, *)
enum StrikethroughAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveStrikethrough"
    static let inheritedByAddedText = true
}

@available(macOS 26, *)
enum HeadingLevelAttribute: CodableAttributedStringKey {
    typealias Value = Int
    static let name = "groveHeadingLevel"
    static let inheritedByAddedText = false
    static let runBoundaries: AttributedString.AttributeRunBoundaries = .paragraph
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition> = [.textChanged]
}

@available(macOS 26, *)
enum BlockQuoteAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveBlockQuote"
    static let inheritedByAddedText = false
    static let runBoundaries: AttributedString.AttributeRunBoundaries = .paragraph
}

@available(macOS 26, *)
enum ListItemAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveListItem"
    static let inheritedByAddedText = false
    static let runBoundaries: AttributedString.AttributeRunBoundaries = .paragraph
}

@available(macOS 26, *)
enum CodeBlockAttribute: CodableAttributedStringKey {
    typealias Value = String // language hint
    static let name = "groveCodeBlock"
    static let inheritedByAddedText = false
    static let runBoundaries: AttributedString.AttributeRunBoundaries = .paragraph
}

@available(macOS 26, *)
enum WikiLinkAttribute: CodableAttributedStringKey {
    typealias Value = String // linked title
    static let name = "groveWikiLink"
    static let inheritedByAddedText = false
}

@available(macOS 26, *)
enum LinkAttribute: CodableAttributedStringKey {
    typealias Value = String // URL string
    static let name = "groveLink"
    static let inheritedByAddedText = false
}

@available(macOS 26, *)
enum MarkdownMarkerAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "groveMarkdownMarker"
    static let inheritedByAddedText = false
}

// MARK: - Attribute Scope

@available(macOS 26, *)
extension AttributeScopes {
    struct GroveAttributes: AttributeScope {
        let bold: BoldAttribute
        let italic: ItalicAttribute
        let inlineCode: InlineCodeAttribute
        let strikethrough: StrikethroughAttribute
        let headingLevel: HeadingLevelAttribute
        let blockQuote: BlockQuoteAttribute
        let listItem: ListItemAttribute
        let codeBlock: CodeBlockAttribute
        let wikiLink: WikiLinkAttribute
        let mdLink: LinkAttribute
        let markdownMarker: MarkdownMarkerAttribute

        let swiftUI: AttributeScopes.SwiftUIAttributes
    }

    var grove: GroveAttributes.Type { GroveAttributes.self }
}

@available(macOS 26, *)
extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.GroveAttributes, T>) -> T {
        self[T.self]
    }
}

// MARK: - Converter

@available(macOS 26, *)
struct MarkdownAttributedStringConverter {

    /// Parse a markdown string into an AttributedString with Grove semantic attributes.
    func attributedString(from markdown: String) -> AttributedString {
        let document = MarkdownDocument(markdown)
        var result = AttributedString(markdown)

        for block in document.blocks {
            switch block.kind {
            case .heading(let heading):
                applyMarkerAttribute(in: heading.markerRange, to: &result)
                applyMarkerAttribute(in: heading.spacingRange, to: &result)
                mutateRange(heading.contentRange, in: &result) { substring in
                    substring.headingLevel = heading.level
                }

            case .blockquote(let blockquote):
                for line in blockquote.lines {
                    applyMarkerAttribute(in: line.prefixRange, to: &result)
                    mutateRange(line.contentRange, in: &result) { substring in
                        substring.blockQuote = true
                    }
                }

            case .bulletList(let list):
                for item in list.items {
                    applyMarkerAttribute(in: item.prefixRange, to: &result)
                    mutateRange(item.contentRange, in: &result) { substring in
                        substring.listItem = true
                    }
                }

            case .codeBlock(let codeBlock):
                applyMarkerAttribute(in: codeBlock.openingFenceRange, to: &result)
                if let closingFenceRange = codeBlock.closingFenceRange {
                    applyMarkerAttribute(in: closingFenceRange, to: &result)
                }
                if let contentRange = codeBlock.contentRange {
                    mutateRange(contentRange, in: &result) { substring in
                        substring.codeBlock = codeBlock.language ?? "plain"
                    }
                }

            case .paragraph:
                break
            }
        }

        for span in document.inlineSpans {
            for markerRange in span.markerRanges {
                applyMarkerAttribute(in: markerRange, to: &result)
            }

            switch span.kind {
            case .bold:
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.bold = true
                }
            case .italic:
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.italic = true
                }
            case .boldItalic:
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.bold = true
                    substring.italic = true
                }
            case .strikethrough:
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.strikethrough = true
                }
            case .inlineCode:
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.inlineCode = true
                }
            case .wikiLink(let title):
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.wikiLink = title
                }
            case .link(let url):
                mutateRange(span.contentRange, in: &result) { substring in
                    substring.mdLink = url
                }
            }
        }

        return result
    }

    /// Serialize an AttributedString back to markdown.
    func markdown(from attributedString: AttributedString) -> String {
        String(attributedString.characters)
    }

    private func applyMarkerAttribute(in range: Range<Int>, to attributedString: inout AttributedString) {
        mutateRange(range, in: &attributedString) { substring in
            substring.markdownMarker = true
        }
    }

    private func mutateRange(
        _ range: Range<Int>,
        in attributedString: inout AttributedString,
        _ mutation: (inout AttributedSubstring) -> Void
    ) {
        guard range.lowerBound < range.upperBound else { return }
        let lower = attributedString.index(attributedString.startIndex, offsetByCharacters: range.lowerBound)
        let upper = attributedString.index(attributedString.startIndex, offsetByCharacters: range.upperBound)
        mutation(&attributedString[lower..<upper])
    }
}
#endif
