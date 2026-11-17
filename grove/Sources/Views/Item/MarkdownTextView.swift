import SwiftUI

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let markdown: String
    /// Type metrics shared with the live editor — `.prose` matches
    /// `RichMarkdownEditor(proseMode: true)` so reflections do not resize
    /// between reading and editing.
    var scale: MarkdownTypeSpec.Scale = .compact
    var onWikiLinkTap: ((String) -> Void)?

    private var document: MarkdownDocument {
        MarkdownDocument(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: scale.blockSpacing) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownDocument.Block) -> some View {
        switch block.kind {
        case .heading(let heading):
            headingView(heading)

        case .codeBlock(let codeBlock):
            SyntaxHighlightedCodeView(
                code: codeBlock.contentRange.map(document.text(in:)) ?? "",
                language: codeBlock.language,
                scale: scale
            )

        case .blockquote(let blockquote):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Array(blockquote.lines.enumerated()), id: \.offset) { _, line in
                        if !document.text(in: line.contentRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            renderInlineText(range: line.contentRange, style: .body)
                        }
                    }
                }
                .padding(.leading, Spacing.md)
            }
            .foregroundStyle(Color.textTertiary)

        case .bulletList(let list):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    listRow(indentation: item.indentation, contentRange: item.contentRange) {
                        Text("\u{2022}")
                            .font(.custom(MarkdownTypeSpec.FontName.body, size: scale.bodySize))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

        case .orderedList(let list):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    listRow(indentation: item.indentation, contentRange: item.contentRange) {
                        Text("\(item.number).")
                            .font(.custom(MarkdownTypeSpec.FontName.mono, size: scale.monoSize))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

        case .paragraph(let paragraph):
            renderInlineText(range: paragraph.textRange, style: .body)
        }
    }

    @ViewBuilder
    private func listRow<Marker: View>(
        indentation: Int,
        contentRange: Range<Int>,
        @ViewBuilder marker: () -> Marker
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xsm) {
            marker()
            renderInlineText(range: contentRange, style: .body)
        }
        .padding(.leading, CGFloat(MarkdownTypeSpec.nestingLevel(forIndentation: indentation)) * scale.listNestIndent)
    }

    @ViewBuilder
    private func renderInlineText(range: Range<Int>, style: InlineStyle) -> some View {
        Text(attributedText(in: range, style: style))
            .lineSpacing(scale.lineSpacing)
            .tint(Color.textSecondary)
            .environment(\.openURL, OpenURLAction(handler: handleOpenURL))
    }

    private enum InlineStyle {
        case body
        case heading(level: Int)
    }

    private func attributedText(in range: Range<Int>, style: InlineStyle) -> AttributedString {
        let presentation = document.inlinePresentation(in: range)
        var attributed = AttributedString(presentation.text)

        let regularFont: Font
        let boldFont: Font
        let italicFont: Font
        let boldItalicFont: Font

        switch style {
        case .body:
            let size = scale.bodySize
            regularFont = .custom(MarkdownTypeSpec.FontName.body, size: size)
            // IBM Plex Sans ships no SemiBold face; Medium is the heaviest
            // bundled weight and is what the live editor renders too.
            boldFont = .custom(MarkdownTypeSpec.FontName.bodyEmphasis, size: size)
            italicFont = .custom(MarkdownTypeSpec.FontName.body, size: size).italic()
            boldItalicFont = .custom(MarkdownTypeSpec.FontName.bodyEmphasis, size: size).italic()
        case .heading(let level):
            let size = scale.headingSize(forLevel: level)
            regularFont = .custom(MarkdownTypeSpec.FontName.heading, size: size)
            boldFont = .custom(MarkdownTypeSpec.FontName.headingEmphasis, size: size)
            italicFont = .custom(MarkdownTypeSpec.FontName.headingItalic, size: size)
            boldItalicFont = .custom(MarkdownTypeSpec.FontName.headingEmphasisItalic, size: size)
        }

        let codeFont = Font.custom(MarkdownTypeSpec.FontName.mono, size: scale.monoSize)

        for run in attributed.runs {
            attributed[run.range].font = regularFont
        }

        for span in presentation.spans {
            let lower = attributed.index(attributed.startIndex, offsetByCharacters: span.range.lowerBound)
            let upper = attributed.index(attributed.startIndex, offsetByCharacters: span.range.upperBound)
            let localRange = lower..<upper

            switch span.kind {
            case .bold:
                attributed[localRange].font = boldFont
            case .italic:
                attributed[localRange].font = italicFont
            case .boldItalic:
                attributed[localRange].font = boldItalicFont
            case .strikethrough:
                attributed[localRange].strikethroughStyle = .single
            case .inlineCode:
                attributed[localRange].font = codeFont
            case .wikiLink(let title):
                attributed[localRange].link = wikiLinkURL(for: title)
            case .link(let url):
                if let destination = URL(string: url) {
                    attributed[localRange].link = destination
                }
            }
        }

        return attributed
    }

    private func wikiLinkURL(for title: String) -> URL? {
        var components = URLComponents()
        components.scheme = "grove-wikilink"
        components.host = "item"
        components.queryItems = [URLQueryItem(name: "title", value: title)]
        return components.url
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "grove-wikilink" else {
            return .systemAction
        }

        guard let title = wikiLinkTitle(from: url), !title.isEmpty else {
            return .handled
        }

        onWikiLinkTap?(title)
        return .handled
    }

    private func wikiLinkTitle(from url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let title = components.queryItems?.first(where: { $0.name == "title" })?.value,
           !title.isEmpty {
            return title
        }

        if let hostTitle = url.host(percentEncoded: false), !hostTitle.isEmpty {
            return hostTitle
        }

        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawPath.isEmpty else { return nil }
        return rawPath.removingPercentEncoding ?? rawPath
    }

    @ViewBuilder
    private func headingView(_ heading: MarkdownDocument.Heading) -> some View {
        let text = Text(attributedText(in: heading.contentRange, style: .heading(level: heading.level)))
            .tint(Color.textSecondary)
            .environment(\.openURL, OpenURLAction(handler: handleOpenURL))

        switch heading.level {
        case 1:
            text
                .padding(.top, Spacing.sm)
        case 2:
            text
                .padding(.top, Spacing.xsm)
        case 3:
            text
                .padding(.top, Spacing.xs)
        default:
            text
                .padding(.top, 2)
        }
    }
}

// MARK: - Syntax Highlighted Code View

private struct SyntaxHighlightedCodeView: View {
    let code: String
    let language: String?
    var scale: MarkdownTypeSpec.Scale = .compact

    private var codeSize: CGFloat { scale.monoSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            if let lang = language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.custom(MarkdownTypeSpec.FontName.monoEmphasis, size: 9))
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xs)
            }

            // Highlighted code
            highlightedText
                .font(.custom(MarkdownTypeSpec.FontName.mono, size: codeSize))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, language != nil ? 6 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
    }

    private var highlightedText: Text {
        let tokens = tokenize(code: code, language: normalizedLanguage)
        return tokens.reduce(Text("")) { result, token in
            var piece = Text(token.text).foregroundStyle(token.color)
            if token.isEmphasized {
                piece = piece.font(.custom(MarkdownTypeSpec.FontName.monoEmphasis, size: codeSize))
            }
            return Text("\(result)\(piece)")
        }
    }

    private var normalizedLanguage: String? {
        guard let lang = language?.lowercased() else { return nil }
        switch lang {
        case "swift": return "swift"
        case "python", "py": return "python"
        case "javascript", "js", "typescript", "ts": return "javascript"
        default: return lang
        }
    }

    private struct Token {
        let text: String
        let color: Color
        /// Keywords carry weight instead of hue — the palette is monochrome.
        var isEmphasized: Bool = false
    }

    private func tokenize(code: String, language: String?) -> [Token] {
        guard let language else {
            return [Token(text: code, color: Color.textPrimary)]
        }

        let keywords: Set<String>

        switch language {
        case "swift":
            keywords = ["func", "var", "let", "if", "else", "guard", "return", "import", "struct", "class", "enum", "case", "switch", "for", "while", "in", "protocol", "extension", "private", "public", "internal", "static", "self", "Self", "init", "deinit", "throw", "throws", "try", "catch", "async", "await", "actor", "some", "any", "where", "typealias", "associatedtype", "override", "final", "lazy", "weak", "unowned", "mutating", "nonmutating", "convenience", "required", "defer", "repeat", "break", "continue", "fallthrough", "do", "is", "as", "nil", "true", "false", "super"]
        case "python":
            keywords = ["def", "class", "if", "elif", "else", "for", "while", "in", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass", "break", "continue", "and", "or", "not", "is", "None", "True", "False", "del", "global", "nonlocal", "assert", "async", "await"]
        case "javascript":
            keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "return", "throw", "try", "catch", "finally", "new", "delete", "typeof", "instanceof", "in", "of", "class", "extends", "super", "import", "export", "default", "from", "as", "async", "await", "yield", "this", "null", "undefined", "true", "false", "void"]
        default:
            return [Token(text: code, color: Color.textPrimary)]
        }

        return highlightCode(code, keywords: keywords)
    }

    private func highlightCode(_ code: String, keywords: Set<String>) -> [Token] {
        var tokens: [Token] = []
        var i = code.startIndex

        // Monochrome ink scale: hierarchy comes from tone + weight, not hue.
        let defaultColor = Color.textPrimary
        let keywordColor = Color.textPrimary        // primary ink + SemiBold
        let stringColor = Color.textSecondary       // mid gray
        let commentColor = Color.textTertiary       // light gray

        while i < code.endIndex {
            let ch = code[i]

            // Line comment
            if ch == "/" && code.index(after: i) < code.endIndex && code[code.index(after: i)] == "/" {
                let start = i
                while i < code.endIndex && code[i] != "\n" {
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: commentColor))
                continue
            }

            // Block comment
            if ch == "/" && code.index(after: i) < code.endIndex && code[code.index(after: i)] == "*" {
                let start = i
                i = code.index(i, offsetBy: 2)
                while i < code.endIndex {
                    if code[i] == "*" && code.index(after: i) < code.endIndex && code[code.index(after: i)] == "/" {
                        i = code.index(i, offsetBy: 2)
                        break
                    }
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: commentColor))
                continue
            }

            // Python # comments
            if ch == "#" {
                let start = i
                while i < code.endIndex && code[i] != "\n" {
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: commentColor))
                continue
            }

            // Strings (double or single quote)
            if ch == "\"" || ch == "'" {
                let quote = ch
                let start = i
                i = code.index(after: i)
                while i < code.endIndex && code[i] != quote {
                    if code[i] == "\\" && code.index(after: i) < code.endIndex {
                        i = code.index(i, offsetBy: 2)
                    } else {
                        i = code.index(after: i)
                    }
                }
                if i < code.endIndex { i = code.index(after: i) }
                tokens.append(Token(text: String(code[start..<i]), color: stringColor))
                continue
            }

            // Numbers
            if ch.isNumber || (ch == "." && i < code.endIndex && code.index(after: i) < code.endIndex && code[code.index(after: i)].isNumber) {
                let start = i
                while i < code.endIndex && (code[i].isNumber || code[i] == "." || code[i] == "_") {
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: defaultColor))
                continue
            }

            // Words (identifiers/keywords)
            if ch.isLetter || ch == "_" || ch == "@" {
                let start = i
                i = code.index(after: i)
                while i < code.endIndex && (code[i].isLetter || code[i].isNumber || code[i] == "_") {
                    i = code.index(after: i)
                }
                let word = String(code[start..<i])
                if keywords.contains(word) || word.hasPrefix("@") {
                    tokens.append(Token(text: word, color: keywordColor, isEmphasized: true))
                } else {
                    tokens.append(Token(text: word, color: defaultColor))
                }
                continue
            }

            // Whitespace and punctuation
            tokens.append(Token(text: String(ch), color: defaultColor))
            i = code.index(after: i)
        }

        return tokens
    }
}
