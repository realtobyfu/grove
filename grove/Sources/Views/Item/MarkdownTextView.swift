import SwiftUI

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let markdown: String
    var onWikiLinkTap: ((String) -> Void)?

    private var document: MarkdownDocument {
        MarkdownDocument(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                language: codeBlock.language
            )

        case .blockquote(let blockquote):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(blockquote.lines.enumerated()), id: \.offset) { _, line in
                        if !document.text(in: line.contentRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            renderInlineText(range: line.contentRange, style: .body)
                        }
                    }
                }
                .padding(.leading, 10)
            }
            .foregroundStyle(Color.textTertiary)

        case .bulletList(let list):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                            .font(.custom("IBMPlexSans-Regular", size: 13))
                            .foregroundStyle(Color.textSecondary)
                        renderInlineText(range: item.contentRange, style: .body)
                    }
                }
            }

        case .paragraph(let paragraph):
            renderInlineText(range: paragraph.textRange, style: .body)
        }
    }

    @ViewBuilder
    private func renderInlineText(range: Range<Int>, style: InlineStyle) -> some View {
        Text(attributedText(in: range, style: style))
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
            regularFont = .custom("IBMPlexSans-Regular", size: 13)
            boldFont = .custom("IBMPlexSans-Medium", size: 13)
            italicFont = .custom("IBMPlexSans-Regular", size: 13).italic()
            boldItalicFont = .custom("IBMPlexSans-Medium", size: 13).italic()
        case .heading(let level):
            let size: CGFloat
            switch level {
            case 1:
                size = 22
            case 2:
                size = 18
            case 3:
                size = 16
            default:
                size = 14
            }
            regularFont = .custom("Newsreader-Medium", size: size)
            boldFont = .custom("Newsreader-SemiBold", size: size)
            italicFont = .custom("Newsreader-MediumItalic", size: size)
            boldItalicFont = .custom("Newsreader-SemiBoldItalic", size: size)
        }

        let codeFont = Font.custom("IBMPlexMono-Regular", size: 12)

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
                .padding(.top, 8)
        case 2:
            text
                .padding(.top, 6)
        case 3:
            text
                .padding(.top, 4)
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
