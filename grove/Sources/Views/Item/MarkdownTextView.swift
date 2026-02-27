import SwiftUI

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let markdown: String
    var onWikiLinkTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case codeBlock(language: String?, code: String)
        case blockquote(lines: [String])
        case bulletList(items: [String])
        case paragraph(text: String)
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                if i < lines.count { i += 1 }
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level >= 1 && level <= 6 && !text.isEmpty {
                    blocks.append(.heading(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // Blockquote (> prefix)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("> ") || line == ">" {
                var quoteLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">") {
                    quoteLines.append(lines[i].hasPrefix("> ") ? String(lines[i].dropFirst(2)) : "")
                    i += 1
                }
                blocks.append(.blockquote(lines: quoteLines))
                continue
            }

            // Bullet list (- or * prefix, supports indentation)
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                var listItems: [String] = []
                while i < lines.count {
                    let current = lines[i].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix("- ") {
                        listItems.append(String(current.dropFirst(2)))
                    } else if current.hasPrefix("* ") {
                        listItems.append(String(current.dropFirst(2)))
                    } else if current.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.bulletList(items: listItems))
                continue
            }

            // Empty line -- skip
            if trimmedLine.isEmpty {
                i += 1
                continue
            }

            // Paragraph: collect consecutive non-empty, non-special lines
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty
                    || nextLine.hasPrefix("#")
                    || nextLine.hasPrefix("```")
                    || nextLine.hasPrefix("> ")
                    || nextLine == ">"
                    || nextTrimmed.hasPrefix("- ")
                    || nextTrimmed.hasPrefix("* ") {
                    break
                }
                paragraphLines.append(nextLine)
                i += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .codeBlock(let language, let code):
            SyntaxHighlightedCodeView(code: code, language: language)

        case .blockquote(let lines):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, qLine in
                        let qTrimmed = qLine.trimmingCharacters(in: .whitespaces)
                        if qTrimmed.hasPrefix("- ") || qTrimmed.hasPrefix("* ") {
                            let bulletText = qTrimmed.hasPrefix("- ") ? String(qTrimmed.dropFirst(2)) : String(qTrimmed.dropFirst(2))
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\u{2022}")
                                    .font(.custom("IBMPlexSans-Regular", size: 13))
                                    .foregroundStyle(Color.textTertiary)
                                renderParagraphWithWikiLinks(bulletText)
                            }
                        } else if !qTrimmed.isEmpty {
                            renderParagraphWithWikiLinks(qLine)
                        }
                    }
                }
                .padding(.leading, 10)
            }
            .foregroundStyle(Color.textTertiary)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, itemText in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                            .font(.custom("IBMPlexSans-Regular", size: 13))
                            .foregroundStyle(Color.textSecondary)
                        renderParagraphWithWikiLinks(itemText)
                    }
                }
            }

        case .paragraph(let text):
            renderParagraphWithWikiLinks(text)
        }
    }

    @ViewBuilder
    private func renderParagraphWithWikiLinks(_ text: String) -> some View {
        Text(attributedTextWithWikiLinks(text))
            .font(.custom("IBMPlexSans-Regular", size: 13))
            .tint(Color.textSecondary)
            .environment(\.openURL, OpenURLAction(handler: handleOpenURL))
    }

    private struct TextSegment {
        let text: String
        let isWikiLink: Bool
    }

    private func attributedTextWithWikiLinks(_ text: String) -> AttributedString {
        let segments = parseWikiLinks(in: text)
        guard segments.contains(where: { $0.isWikiLink }) else {
            return parseInlineMarkdown(text)
        }

        var combined = AttributedString()
        for segment in segments {
            if segment.isWikiLink {
                var linkSegment = AttributedString(segment.text)
                if let url = wikiLinkURL(for: segment.text) {
                    linkSegment.link = url
                }
                combined.append(linkSegment)
            } else {
                combined.append(parseInlineMarkdown(segment.text))
            }
        }

        return combined
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        guard var result = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(text)
        }

        // Post-process to apply explicit fonts for bold/italic since
        // SwiftUI can't resolve weight/style variants for custom fonts
        // from presentation intents alone.
        let bodyFont = Font.custom("IBMPlexSans-Regular", size: 13)
        let boldFont = Font.custom("IBMPlexSans-Medium", size: 13)
        let italicFont = Font.custom("IBMPlexSans-Regular", size: 13).italic()
        let boldItalicFont = Font.custom("IBMPlexSans-Medium", size: 13).italic()
        let codeFont = Font.custom("IBMPlexMono-Regular", size: 12)

        for run in result.runs {
            let range = run.range
            guard let intent = run.inlinePresentationIntent else {
                result[range].font = bodyFont
                continue
            }
            let isBold = intent.contains(.stronglyEmphasized)
            let isItalic = intent.contains(.emphasized)
            let isCode = intent.contains(.code)

            if isCode {
                result[range].font = codeFont
            } else if isBold && isItalic {
                result[range].font = boldItalicFont
            } else if isBold {
                result[range].font = boldFont
            } else if isItalic {
                result[range].font = italicFont
            } else {
                result[range].font = bodyFont
            }
        }

        return result
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

    private func parseWikiLinks(in text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text[text.startIndex...]

        while let openRange = remaining.range(of: "[[") {
            let before = remaining[remaining.startIndex..<openRange.lowerBound]
            if !before.isEmpty {
                segments.append(TextSegment(text: String(before), isWikiLink: false))
            }

            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "]]") {
                let linkTitle = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                segments.append(TextSegment(text: linkTitle, isWikiLink: true))
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                segments.append(TextSegment(text: String(remaining[openRange.lowerBound...]), isWikiLink: false))
                remaining = remaining[remaining.endIndex...]
            }
        }

        if !remaining.isEmpty {
            segments.append(TextSegment(text: String(remaining), isWikiLink: false))
        }

        return segments
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let cleanText = text.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        let attributed = (try? AttributedString(markdown: cleanText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cleanText)

        switch level {
        case 1:
            Text(attributed)
                .font(.custom("Newsreader", size: 22))
                .fontWeight(.semibold)
                .padding(.top, 8)
        case 2:
            Text(attributed)
                .font(.custom("Newsreader", size: 18))
                .fontWeight(.medium)
                .padding(.top, 6)
        case 3:
            Text(attributed)
                .font(.custom("Newsreader", size: 16))
                .fontWeight(.medium)
                .padding(.top, 4)
        default:
            Text(attributed)
                .font(.custom("IBMPlexSans-Regular", size: 14))
                .fontWeight(.semibold)
                .padding(.top, 2)
        }
    }
}

// MARK: - Syntax Highlighted Code View

private struct SyntaxHighlightedCodeView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            if let lang = language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.custom("IBMPlexMono", size: 9))
                    .fontWeight(.medium)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            // Highlighted code
            highlightedText
                .font(.custom("IBMPlexMono", size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, language != nil ? 6 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
    }

    private var highlightedText: Text {
        let tokens = tokenize(code: code, language: normalizedLanguage)
        return tokens.reduce(Text("")) { result, token in
            result + Text(token.text)
                .foregroundStyle(token.color)
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
    }

    private func tokenize(code: String, language: String?) -> [Token] {
        guard let language else {
            return [Token(text: code, color: Color(hex: "1A1A1A"))]
        }

        let keywords: Set<String>
        let typeKeywords: Set<String>
        let builtins: Set<String>

        switch language {
        case "swift":
            keywords = ["func", "var", "let", "if", "else", "guard", "return", "import", "struct", "class", "enum", "case", "switch", "for", "while", "in", "protocol", "extension", "private", "public", "internal", "static", "self", "Self", "init", "deinit", "throw", "throws", "try", "catch", "async", "await", "actor", "some", "any", "where", "typealias", "associatedtype", "override", "final", "lazy", "weak", "unowned", "mutating", "nonmutating", "convenience", "required", "defer", "repeat", "break", "continue", "fallthrough", "do", "is", "as", "nil", "true", "false", "super"]
            typeKeywords = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Void", "Any", "AnyObject", "Date", "UUID", "Data", "URL", "View", "State", "Binding", "Published", "Observable", "ObservedObject", "StateObject", "EnvironmentObject", "Environment"]
            builtins = ["print", "debugPrint", "fatalError", "precondition", "assert"]
        case "python":
            keywords = ["def", "class", "if", "elif", "else", "for", "while", "in", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass", "break", "continue", "and", "or", "not", "is", "None", "True", "False", "del", "global", "nonlocal", "assert", "async", "await"]
            typeKeywords = ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "type", "object", "bytes", "range", "Exception"]
            builtins = ["print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "isinstance", "hasattr", "getattr", "setattr", "super", "property", "staticmethod", "classmethod", "open", "input"]
        case "javascript":
            keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "return", "throw", "try", "catch", "finally", "new", "delete", "typeof", "instanceof", "in", "of", "class", "extends", "super", "import", "export", "default", "from", "as", "async", "await", "yield", "this", "null", "undefined", "true", "false", "void"]
            typeKeywords = ["Array", "Object", "String", "Number", "Boolean", "Map", "Set", "Promise", "Symbol", "RegExp", "Error", "Date", "JSON", "Math", "console"]
            builtins = ["console", "setTimeout", "setInterval", "fetch", "require", "module", "process"]
        default:
            return [Token(text: code, color: Color(hex: "1A1A1A"))]
        }

        return highlightCode(code, keywords: keywords, typeKeywords: typeKeywords, builtins: builtins)
    }

    private func highlightCode(_ code: String, keywords: Set<String>, typeKeywords: Set<String>, builtins: Set<String>) -> [Token] {
        var tokens: [Token] = []
        var i = code.startIndex

        let defaultColor = Color(hex: "1A1A1A")
        let keywordColor = Color(hex: "6E3A8A")    // purple-ish for keywords
        let typeColor = Color(hex: "2D6A4F")        // green for types
        let stringColor = Color(hex: "9A3412")      // warm brown for strings
        let commentColor = Color(hex: "999999")      // muted for comments
        let numberColor = Color(hex: "1D4ED8")       // blue for numbers
        let builtinColor = Color(hex: "0E7490")      // teal for builtins

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
                tokens.append(Token(text: String(code[start..<i]), color: numberColor))
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
                if keywords.contains(word) {
                    tokens.append(Token(text: word, color: keywordColor))
                } else if typeKeywords.contains(word) {
                    tokens.append(Token(text: word, color: typeColor))
                } else if builtins.contains(word) {
                    tokens.append(Token(text: word, color: builtinColor))
                } else if word.hasPrefix("@") {
                    tokens.append(Token(text: word, color: keywordColor))
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
