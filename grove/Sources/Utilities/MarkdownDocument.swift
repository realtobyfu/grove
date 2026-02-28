import Foundation

struct MarkdownDocument: Sendable {
    let source: String
    let blocks: [Block]
    let inlineSpans: [InlineSpan]

    init(_ source: String) {
        self.source = source

        let lines = Self.makeLineRecords(from: source)
        let result = Self.parseBlocks(in: source, lines: lines)
        blocks = result.blocks
        inlineSpans = result.inlineSpans.sorted {
            if $0.fullRange.lowerBound == $1.fullRange.lowerBound {
                return $0.fullRange.upperBound > $1.fullRange.upperBound
            }
            return $0.fullRange.lowerBound < $1.fullRange.lowerBound
        }
    }

    struct Block: Sendable {
        let range: Range<Int>
        let kind: Kind
    }

    enum Kind: Sendable {
        case heading(Heading)
        case paragraph(Paragraph)
        case blockquote(Blockquote)
        case bulletList(BulletList)
        case codeBlock(CodeBlock)
    }

    struct Heading: Sendable {
        let level: Int
        let markerRange: Range<Int>
        let spacingRange: Range<Int>
        let contentRange: Range<Int>
    }

    struct Paragraph: Sendable {
        let textRange: Range<Int>
        let lineRanges: [Range<Int>]
    }

    struct PrefixedLine: Sendable {
        let lineRange: Range<Int>
        let prefixRange: Range<Int>
        let contentRange: Range<Int>
    }

    struct Blockquote: Sendable {
        let lines: [PrefixedLine]
    }

    struct ListItem: Sendable {
        let lineRange: Range<Int>
        let prefixRange: Range<Int>
        let contentRange: Range<Int>
        let indentation: Int
    }

    struct BulletList: Sendable {
        let items: [ListItem]
    }

    struct CodeBlock: Sendable {
        let language: String?
        let openingFenceRange: Range<Int>
        let contentRange: Range<Int>?
        let closingFenceRange: Range<Int>?
    }

    struct InlineSpan: Sendable {
        enum Kind: Sendable {
            case bold
            case italic
            case boldItalic
            case strikethrough
            case inlineCode
            case wikiLink(title: String)
            case link(url: String)
        }

        let kind: Kind
        let fullRange: Range<Int>
        let contentRange: Range<Int>

        var markerRanges: [Range<Int>] {
            var ranges: [Range<Int>] = []
            if fullRange.lowerBound < contentRange.lowerBound {
                ranges.append(fullRange.lowerBound..<contentRange.lowerBound)
            }
            if contentRange.upperBound < fullRange.upperBound {
                ranges.append(contentRange.upperBound..<fullRange.upperBound)
            }
            return ranges
        }
    }

    struct InlinePresentation: Sendable {
        struct StyledSpan: Sendable {
            let range: Range<Int>
            let kind: InlineSpan.Kind
        }

        let text: String
        let spans: [StyledSpan]
    }

    func text(in range: Range<Int>) -> String {
        let lower = stringIndex(at: range.lowerBound)
        let upper = stringIndex(at: range.upperBound)
        return String(source[lower..<upper])
    }

    func inlineSpans(in range: Range<Int>) -> [InlineSpan] {
        inlineSpans.filter { $0.fullRange.overlaps(range) }
    }

    func inlinePresentation(in range: Range<Int>) -> InlinePresentation {
        let relevantSpans = inlineSpans(in: range)
        let exclusions = Self.mergeRanges(
            relevantSpans.flatMap { span in
                span.markerRanges.compactMap { Self.intersection(of: $0, and: range) }
            }
        )

        var visible = ""
        var cursor = range.lowerBound
        for exclusion in exclusions {
            if cursor < exclusion.lowerBound {
                visible += text(in: cursor..<exclusion.lowerBound)
            }
            cursor = max(cursor, exclusion.upperBound)
        }
        if cursor < range.upperBound {
            visible += text(in: cursor..<range.upperBound)
        }

        let styledSpans = relevantSpans.compactMap { span -> InlinePresentation.StyledSpan? in
            guard let contentRange = Self.intersection(of: span.contentRange, and: range) else {
                return nil
            }

            let visibleStart = Self.visibleOffset(
                for: contentRange.lowerBound,
                in: range,
                excluding: exclusions
            )
            let visibleEnd = Self.visibleOffset(
                for: contentRange.upperBound,
                in: range,
                excluding: exclusions
            )
            guard visibleEnd > visibleStart else { return nil }
            return InlinePresentation.StyledSpan(range: visibleStart..<visibleEnd, kind: span.kind)
        }

        return InlinePresentation(text: visible, spans: styledSpans)
    }

    private func stringIndex(at offset: Int) -> String.Index {
        source.index(source.startIndex, offsetBy: min(max(0, offset), source.count))
    }

    private struct LineRecord {
        let textRange: Range<Int>
        let text: String

        var isBlank: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private struct ParseResult {
        var blocks: [Block]
        var inlineSpans: [InlineSpan]
    }

    private static func makeLineRecords(from source: String) -> [LineRecord] {
        guard !source.isEmpty else { return [] }

        var lines: [LineRecord] = []
        var lineStart = source.startIndex
        var startOffset = 0

        while lineStart < source.endIndex {
            var cursor = lineStart
            var lineLength = 0

            while cursor < source.endIndex, source[cursor] != "\n" {
                cursor = source.index(after: cursor)
                lineLength += 1
            }

            let textRange = startOffset..<(startOffset + lineLength)
            let text = String(source[lineStart..<cursor])
            lines.append(LineRecord(textRange: textRange, text: text))

            guard cursor < source.endIndex else { break }

            lineStart = source.index(after: cursor)
            startOffset += lineLength + 1
        }

        return lines
    }

    private static func parseBlocks(in source: String, lines: [LineRecord]) -> ParseResult {
        var blocks: [Block] = []
        var inlineSpans: [InlineSpan] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if let openingFence = codeFence(for: line) {
                let openingLine = line
                let language = openingFence.language
                index += 1

                var contentLines: [LineRecord] = []
                var closingFenceRange: Range<Int>?

                while index < lines.count {
                    if let closingFence = codeFence(for: lines[index]) {
                        closingFenceRange = closingFence.fenceRange
                        index += 1
                        break
                    }

                    contentLines.append(lines[index])
                    index += 1
                }

                let blockEnd = closingFenceRange?.upperBound ?? contentLines.last?.textRange.upperBound ?? openingLine.textRange.upperBound
                let contentRange = contentLines.isEmpty
                    ? nil
                    : contentLines.first!.textRange.lowerBound..<contentLines.last!.textRange.upperBound
                let codeBlock = CodeBlock(
                    language: language,
                    openingFenceRange: openingFence.fenceRange,
                    contentRange: contentRange,
                    closingFenceRange: closingFenceRange
                )
                blocks.append(
                    Block(
                        range: openingLine.textRange.lowerBound..<blockEnd,
                        kind: .codeBlock(codeBlock)
                    )
                )
                continue
            }

            if let heading = heading(for: line) {
                blocks.append(Block(range: line.textRange, kind: .heading(heading)))
                inlineSpans.append(contentsOf: parseInline(in: source, range: heading.contentRange))
                index += 1
                continue
            }

            if let quoteLine = blockquoteLine(for: line) {
                var quoteLines = [quoteLine]
                index += 1

                while index < lines.count, let nextQuoteLine = blockquoteLine(for: lines[index]) {
                    quoteLines.append(nextQuoteLine)
                    index += 1
                }

                if let first = quoteLines.first, let last = quoteLines.last {
                    blocks.append(
                        Block(
                            range: first.lineRange.lowerBound..<last.lineRange.upperBound,
                            kind: .blockquote(Blockquote(lines: quoteLines))
                        )
                    )
                    for quotedLine in quoteLines {
                        inlineSpans.append(contentsOf: parseInline(in: source, range: quotedLine.contentRange))
                    }
                }

                continue
            }

            if let firstListItem = listItem(for: line) {
                var items = [firstListItem]
                index += 1

                while index < lines.count, let nextItem = listItem(for: lines[index]) {
                    items.append(nextItem)
                    index += 1
                }

                if let first = items.first, let last = items.last {
                    blocks.append(
                        Block(
                            range: first.lineRange.lowerBound..<last.lineRange.upperBound,
                            kind: .bulletList(BulletList(items: items))
                        )
                    )
                    for item in items {
                        inlineSpans.append(contentsOf: parseInline(in: source, range: item.contentRange))
                    }
                }

                continue
            }

            if line.isBlank {
                index += 1
                continue
            }

            var paragraphLines: [LineRecord] = [line]
            index += 1

            while index < lines.count {
                let nextLine = lines[index]
                if nextLine.isBlank
                    || codeFence(for: nextLine) != nil
                    || heading(for: nextLine) != nil
                    || blockquoteLine(for: nextLine) != nil
                    || listItem(for: nextLine) != nil {
                    break
                }

                paragraphLines.append(nextLine)
                index += 1
            }

            if let first = paragraphLines.first, let last = paragraphLines.last {
                let paragraph = Paragraph(
                    textRange: first.textRange.lowerBound..<last.textRange.upperBound,
                    lineRanges: paragraphLines.map(\.textRange)
                )
                blocks.append(Block(range: paragraph.textRange, kind: .paragraph(paragraph)))
                for lineRange in paragraph.lineRanges {
                    inlineSpans.append(contentsOf: parseInline(in: source, range: lineRange))
                }
            }
        }

        return ParseResult(blocks: blocks, inlineSpans: inlineSpans)
    }

    private struct CodeFenceInfo {
        let fenceRange: Range<Int>
        let language: String?
    }

    private static func codeFence(for line: LineRecord) -> CodeFenceInfo? {
        guard line.text.hasPrefix("```") else { return nil }
        let fenceRange = line.textRange.lowerBound..<(line.textRange.lowerBound + 3)
        let language = String(line.text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return CodeFenceInfo(
            fenceRange: fenceRange,
            language: language.isEmpty ? nil : language
        )
    }

    private static func heading(for line: LineRecord) -> Heading? {
        var cursor = line.text.startIndex
        var hashCount = 0

        while cursor < line.text.endIndex, line.text[cursor] == "#", hashCount < 6 {
            hashCount += 1
            cursor = line.text.index(after: cursor)
        }

        guard hashCount > 0 else { return nil }

        let markerLength = hashCount
        let spacingStartOffset = markerLength
        var spacingCursor = cursor
        var spacingLength = 0

        while spacingCursor < line.text.endIndex {
            let character = line.text[spacingCursor]
            guard character == " " || character == "\t" else { break }
            spacingLength += 1
            spacingCursor = line.text.index(after: spacingCursor)
        }

        guard spacingLength > 0 else { return nil }

        let contentStart = line.textRange.lowerBound + spacingStartOffset + spacingLength
        guard contentStart < line.textRange.upperBound else { return nil }

        return Heading(
            level: hashCount,
            markerRange: line.textRange.lowerBound..<(line.textRange.lowerBound + markerLength),
            spacingRange: (line.textRange.lowerBound + spacingStartOffset)..<contentStart,
            contentRange: contentStart..<line.textRange.upperBound
        )
    }

    private static func blockquoteLine(for line: LineRecord) -> PrefixedLine? {
        let characters = Array(line.text)
        var index = 0

        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }

        guard index < characters.count, characters[index] == ">" else { return nil }
        index += 1

        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }

        let contentStart = line.textRange.lowerBound + index
        return PrefixedLine(
            lineRange: line.textRange,
            prefixRange: line.textRange.lowerBound..<contentStart,
            contentRange: contentStart..<line.textRange.upperBound
        )
    }

    private static func listItem(for line: LineRecord) -> ListItem? {
        let characters = Array(line.text)
        var index = 0

        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }

        let indentation = index
        guard index < characters.count, characters[index] == "-" || characters[index] == "*" else {
            return nil
        }
        index += 1

        var spacerCount = 0
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            spacerCount += 1
            index += 1
        }

        guard spacerCount > 0 else { return nil }

        let contentStart = line.textRange.lowerBound + index
        return ListItem(
            lineRange: line.textRange,
            prefixRange: line.textRange.lowerBound..<contentStart,
            contentRange: contentStart..<line.textRange.upperBound,
            indentation: indentation
        )
    }

    private static func parseInline(in source: String, range: Range<Int>) -> [InlineSpan] {
        guard range.lowerBound < range.upperBound else { return [] }

        let lower = source.index(source.startIndex, offsetBy: range.lowerBound)
        let upper = source.index(source.startIndex, offsetBy: range.upperBound)
        let substring = String(source[lower..<upper])
        guard !substring.isEmpty else { return [] }

        var spans: [InlineSpan] = []
        appendInlineMatches(
            pattern: #"\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { _, _ in .boldItalic },
            into: &spans
        )
        appendInlineMatches(
            pattern: #"(?<!\*)\*\*(?!\*)(?=\S)(.+?)(?<=\S)(?<!\*)\*\*(?!\*)"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { _, _ in .bold },
            into: &spans
        )
        appendInlineMatches(
            pattern: #"(?<!\*)\*(?!\*)(?=\S)(.+?)(?<=\S)(?<!\*)\*(?!\*)"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { _, _ in .italic },
            into: &spans
        )
        appendInlineMatches(
            pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { _, _ in .strikethrough },
            into: &spans
        )
        appendInlineMatches(
            pattern: #"`([^`]+)`"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { _, _ in .inlineCode },
            into: &spans
        )
        appendInlineMatches(
            pattern: #"\[\[(.+?)\]\]"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { match, text in
                .wikiLink(title: text.substring(with: match.range(at: 1)))
            },
            into: &spans
        )
        appendInlineMatches(
            pattern: #"\[(?!\[)([^\]\n]+)\]\(([^)\n]+)\)"#,
            in: substring,
            baseOffset: range.lowerBound,
            contentGroupIndex: 1,
            kind: { match, text in
                .link(url: text.substring(with: match.range(at: 2)))
            },
            into: &spans
        )
        return spans
    }

    private static func appendInlineMatches(
        pattern: String,
        in text: String,
        baseOffset: Int,
        contentGroupIndex: Int,
        kind: (NSTextCheckingResult, NSString) -> InlineSpan.Kind,
        into spans: inout [InlineSpan]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges > contentGroupIndex,
                  let fullSwiftRange = Range(match.range, in: text),
                  let contentSwiftRange = Range(match.range(at: contentGroupIndex), in: text) else {
                continue
            }

            let fullLower = text.distance(from: text.startIndex, to: fullSwiftRange.lowerBound)
            let fullUpper = text.distance(from: text.startIndex, to: fullSwiftRange.upperBound)
            let contentLower = text.distance(from: text.startIndex, to: contentSwiftRange.lowerBound)
            let contentUpper = text.distance(from: text.startIndex, to: contentSwiftRange.upperBound)

            spans.append(
                InlineSpan(
                    kind: kind(match, nsText),
                    fullRange: (baseOffset + fullLower)..<(baseOffset + fullUpper),
                    contentRange: (baseOffset + contentLower)..<(baseOffset + contentUpper)
                )
            )
        }
    }

    private static func intersection(of lhs: Range<Int>, and rhs: Range<Int>) -> Range<Int>? {
        let lower = max(lhs.lowerBound, rhs.lowerBound)
        let upper = min(lhs.upperBound, rhs.upperBound)
        return lower < upper ? lower..<upper : nil
    }

    private static func mergeRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted {
            if $0.lowerBound == $1.lowerBound {
                return $0.upperBound < $1.upperBound
            }
            return $0.lowerBound < $1.lowerBound
        }

        var merged: [Range<Int>] = [sorted[0]]
        for range in sorted.dropFirst() {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private static func visibleOffset(
        for sourceOffset: Int,
        in baseRange: Range<Int>,
        excluding exclusions: [Range<Int>]
    ) -> Int {
        var removedLength = 0
        for exclusion in exclusions {
            if exclusion.upperBound <= sourceOffset {
                removedLength += exclusion.count
                continue
            }
            if exclusion.lowerBound < sourceOffset {
                removedLength += sourceOffset - exclusion.lowerBound
            }
            break
        }

        return max(0, sourceOffset - baseRange.lowerBound - removedLength)
    }
}
