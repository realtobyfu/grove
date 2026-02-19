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
        let lines = markdown.components(separatedBy: "\n")
        var result = AttributedString()
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block: ```
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }

                let codeText = codeLines.joined(separator: "\n") + "\n"
                var codeAttr = AttributedString(codeText)
                codeAttr.codeBlock = language.isEmpty ? "plain" : language
                result.append(codeAttr)
                continue
            }

            // Heading: # or ##
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level >= 1 && level <= 6 && !text.isEmpty {
                    var headingAttr = applyInlineFormatting(to: text + "\n")
                    for run in headingAttr.runs {
                        headingAttr[run.range].headingLevel = level
                    }
                    result.append(headingAttr)
                    i += 1
                    continue
                }
            }

            // Block quote: >
            if line.hasPrefix("> ") || line == ">" {
                let text = line.hasPrefix("> ") ? String(line.dropFirst(2)) : ""
                var bqAttr = applyInlineFormatting(to: text + "\n")
                for run in bqAttr.runs {
                    bqAttr[run.range].blockQuote = true
                }
                result.append(bqAttr)
                i += 1
                continue
            }

            // List item: - or *
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let text = String(trimmed.dropFirst(2))
                var listAttr = applyInlineFormatting(to: text + "\n")
                for run in listAttr.runs {
                    listAttr[run.range].listItem = true
                }
                result.append(listAttr)
                i += 1
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                result.append(AttributedString("\n"))
                i += 1
                continue
            }

            // Regular paragraph line
            let lineAttr = applyInlineFormatting(to: line + "\n")
            result.append(lineAttr)
            i += 1
        }

        return result
    }

    /// Serialize an AttributedString back to markdown.
    func markdown(from attributedString: AttributedString) -> String {
        String(attributedString.characters)
    }

    // MARK: - Line Serialization

    private func serializeLine(_ attrStr: AttributedString, from start: AttributedString.Index, to end: AttributedString.Index) -> String {
        guard start < attrStr.endIndex else { return "" }
        let clampedEnd = min(end, attrStr.endIndex)

        // Find the first run that contains `start` to read block-level attributes
        guard let firstRun = attrStr[start..<clampedEnd].runs.first else { return "" }

        if let codeBlock = firstRun.codeBlock {
            let lang = codeBlock == "plain" ? "" : codeBlock
            let rawText = String(attrStr.characters[start..<clampedEnd])
            return "```\(lang)\n\(rawText)\n```"
        }

        let headingLevel = firstRun.headingLevel
        let isBlockQuote = firstRun.blockQuote ?? false
        let isListItem = firstRun.listItem ?? false

        // Serialize inline formatting
        let inlineMarkdown = serializeInlineRuns(attrStr, from: start, to: clampedEnd)

        if let level = headingLevel {
            let prefix = String(repeating: "#", count: level) + " "
            return prefix + inlineMarkdown
        } else if isBlockQuote {
            return "> " + inlineMarkdown
        } else if isListItem {
            return "- " + inlineMarkdown
        }

        return inlineMarkdown
    }

    // MARK: - Inline Formatting

    /// Represents a matched inline pattern with its range offsets and content.
    private struct InlineMatch {
        let startOffset: Int
        let endOffset: Int
        let content: String
    }

    /// Find all matches for a regex pattern, returning offset pairs.
    private func findInlineMatches(
        pattern: String,
        in text: String,
        contentGroupIndex: Int = 0
    ) -> [InlineMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let fullNSRange = match.range
            let content: String
            if contentGroupIndex > 0 && match.numberOfRanges > contentGroupIndex {
                content = nsText.substring(with: match.range(at: contentGroupIndex))
            } else {
                content = nsText.substring(with: fullNSRange)
            }
            guard let swiftRange = Range(fullNSRange, in: text) else { return nil }
            let startOffset = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: swiftRange.upperBound)
            return InlineMatch(startOffset: startOffset, endOffset: endOffset, content: content)
        }
    }

    /// Apply inline markdown formatting (bold, italic, code, wiki-links, links, strikethrough).
    private func applyInlineFormatting(to text: String) -> AttributedString {
        var result = AttributedString(text)

        // Wiki-links: [[text]]
        let wikiMatches = findInlineMatches(pattern: #"\[\[(.+?)\]\]"#, in: text, contentGroupIndex: 1)
        for m in wikiMatches {
            let start = result.index(result.startIndex, offsetByCharacters: m.startOffset)
            let end = result.index(result.startIndex, offsetByCharacters: m.endOffset)
            result[start..<end].wikiLink = m.content
        }

        // Links: [text](url)
        if let regex = try? NSRegularExpression(pattern: #"\[(.+?)\]\((.+?)\)"#) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let fullNSRange = match.range
                    let urlRange = match.range(at: 2)
                    let url = nsText.substring(with: urlRange)

                    if let swiftRange = Range(fullNSRange, in: text) {
                        let startOffset = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
                        let endOffset = text.distance(from: text.startIndex, to: swiftRange.upperBound)
                        let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
                        let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)
                        result[attrStart..<attrEnd].mdLink = url
                    }
                }
            }
        }

        // Bold: **text**
        let boldMatches = findInlineMatches(pattern: #"\*\*(.+?)\*\*"#, in: text)
        for m in boldMatches {
            let start = result.index(result.startIndex, offsetByCharacters: m.startOffset)
            let end = result.index(result.startIndex, offsetByCharacters: m.endOffset)
            result[start..<end].bold = true
        }

        // Italic: *text* (not **)
        let italicMatches = findInlineMatches(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: text)
        for m in italicMatches {
            let start = result.index(result.startIndex, offsetByCharacters: m.startOffset)
            let end = result.index(result.startIndex, offsetByCharacters: m.endOffset)
            result[start..<end].italic = true
        }

        // Inline code: `text`
        let codeMatches = findInlineMatches(pattern: #"`([^`]+)`"#, in: text)
        for m in codeMatches {
            let start = result.index(result.startIndex, offsetByCharacters: m.startOffset)
            let end = result.index(result.startIndex, offsetByCharacters: m.endOffset)
            result[start..<end].inlineCode = true
        }

        // Strikethrough: ~~text~~
        let strikeMatches = findInlineMatches(pattern: #"~~(.+?)~~"#, in: text)
        for m in strikeMatches {
            let start = result.index(result.startIndex, offsetByCharacters: m.startOffset)
            let end = result.index(result.startIndex, offsetByCharacters: m.endOffset)
            result[start..<end].strikethrough = true
        }

        return result
    }

    // MARK: - Inline Serialization

    private func serializeInlineRuns(_ attrStr: AttributedString, from start: AttributedString.Index, to end: AttributedString.Index) -> String {
        guard start < end && start < attrStr.endIndex else { return "" }
        let clampedEnd = min(end, attrStr.endIndex)
        guard start < clampedEnd else { return "" }

        var mdResult = ""
        for run in attrStr[start..<clampedEnd].runs {
            let runRange = run.range.clamped(to: start..<clampedEnd)
            let text = String(attrStr.characters[runRange])

            let isBold = run.bold ?? false
            let isItalic = run.italic ?? false
            let isCode = run.inlineCode ?? false
            let isStrike = run.strikethrough ?? false
            let wikiLinkTitle = run.wikiLink
            let linkURL = run.mdLink

            var segment = text

            if wikiLinkTitle != nil {
                segment = "[[" + text + "]]"
            } else if let url = linkURL {
                segment = "[" + text + "](" + url + ")"
            } else {
                if isCode { segment = "`" + segment + "`" }
                if isBold { segment = "**" + segment + "**" }
                if isItalic { segment = "*" + segment + "*" }
                if isStrike { segment = "~~" + segment + "~~" }
            }

            mdResult += segment
        }

        return mdResult
    }
}
