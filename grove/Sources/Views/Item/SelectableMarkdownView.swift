import SwiftUI

// MARK: - Selectable Markdown View (NSTextView-backed for text selection)

#if os(macOS)
struct SelectableMarkdownView: NSViewRepresentable {
    let markdown: String
    var onSelectText: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectText: onSelectText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.borderType = .noBorder

        updateTextView(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSelectText = onSelectText
        textView.delegate = nil
        updateTextView(textView)
        textView.delegate = context.coordinator
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              textView.textStorage?.length ?? 0 > 0 else { return nil }
        let width = proposal.width ?? 400
        textView.frame.size.width = width
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height + (textView.textContainerInset.height * 2))
        return CGSize(width: width, height: max(height, 1))
    }

    private func updateTextView(_ textView: NSTextView) {
        let attributed = markdownToAttributedString(markdown)
        textView.textStorage?.setAttributedString(attributed)
    }

    private func markdownToAttributedString(_ md: String) -> NSAttributedString {
        let document = MarkdownDocument(md)
        let result = NSMutableAttributedString()

        for (index, block) in document.blocks.enumerated() {
            result.append(attributedString(for: block, in: document))

            if let nextBlock = document.blocks.dropFirst(index).first {
                appendSeparator(
                    from: block.range.upperBound,
                    to: nextBlock.range.lowerBound,
                    source: document.source,
                    into: result
                )
            }
        }

        return result
    }

    private func attributedString(
        for block: MarkdownDocument.Block,
        in document: MarkdownDocument
    ) -> NSAttributedString {
        switch block.kind {
        case .heading(let heading):
            return inlineAttributedString(
                in: heading.contentRange,
                style: .heading(level: heading.level),
                document: document
            )

        case .paragraph(let paragraph):
            return inlineAttributedString(
                in: paragraph.textRange,
                style: .body,
                document: document
            )

        case .blockquote(let blockquote):
            let result = NSMutableAttributedString()
            for (index, line) in blockquote.lines.enumerated() {
                let lineString = inlineAttributedString(
                    in: line.contentRange,
                    style: .blockquote,
                    document: document
                )
                result.append(lineString)
                if index < blockquote.lines.count - 1 {
                    result.append(NSAttributedString(string: "\n"))
                }
            }
            return result

        case .bulletList(let list):
            let result = NSMutableAttributedString()
            for (index, item) in list.items.enumerated() {
                result.append(
                    listItemAttributedString(
                        item,
                        document: document
                    )
                )
                if index < list.items.count - 1 {
                    result.append(NSAttributedString(string: "\n"))
                }
            }
            return result

        case .codeBlock(let codeBlock):
            return codeBlockAttributedString(codeBlock, document: document)
        }
    }

    private func appendSeparator(
        from lowerBound: Int,
        to upperBound: Int,
        source: String,
        into result: NSMutableAttributedString
    ) {
        guard lowerBound < upperBound else {
            result.append(NSAttributedString(string: "\n"))
            return
        }

        let startIndex = source.index(source.startIndex, offsetBy: lowerBound)
        let endIndex = source.index(source.startIndex, offsetBy: upperBound)
        let gap = source[startIndex..<endIndex]
        let newlineCount = max(1, gap.reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        })
        result.append(NSAttributedString(string: String(repeating: "\n", count: newlineCount)))
    }

    private enum InlineStyle {
        case body
        case blockquote
        case heading(level: Int)
    }

    private func inlineAttributedString(
        in range: Range<Int>,
        style: InlineStyle,
        document: MarkdownDocument
    ) -> NSAttributedString {
        let presentation = document.inlinePresentation(in: range)
        let attributed = NSMutableAttributedString(
            string: presentation.text,
            attributes: baseAttributes(for: style)
        )

        let fonts = inlineFonts(for: style)
        let codeFont = NSFont(name: "IBMPlexMono-Regular", size: 12)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        for span in presentation.spans {
            let nsRange = NSRange(location: span.range.lowerBound, length: span.range.upperBound - span.range.lowerBound)
            guard nsRange.location != NSNotFound,
                  nsRange.location + nsRange.length <= attributed.length else {
                continue
            }

            switch span.kind {
            case .bold:
                attributed.addAttribute(.font, value: fonts.bold, range: nsRange)
            case .italic:
                attributed.addAttribute(.font, value: fonts.italic, range: nsRange)
            case .boldItalic:
                attributed.addAttribute(.font, value: fonts.boldItalic, range: nsRange)
            case .strikethrough:
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            case .inlineCode:
                attributed.addAttribute(.font, value: codeFont, range: nsRange)
                attributed.addAttribute(
                    .backgroundColor,
                    value: NSColor.windowBackgroundColor.withAlphaComponent(0.5),
                    range: nsRange
                )
            case .wikiLink(let title):
                if let url = wikiLinkURL(for: title) {
                    attributed.addAttribute(.link, value: url, range: nsRange)
                }
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsRange)
            case .link(let urlString):
                if let url = URL(string: urlString) {
                    attributed.addAttribute(.link, value: url, range: nsRange)
                }
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsRange)
            }
        }

        return attributed
    }

    private func listItemAttributedString(
        _ item: MarkdownDocument.ListItem,
        document: MarkdownDocument
    ) -> NSAttributedString {
        let bulletIndent = CGFloat(item.indentation / 2) * 12
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.firstLineHeadIndent = bulletIndent
        paragraphStyle.headIndent = bulletIndent + 14

        let prefix = NSAttributedString(
            string: "\u{2022} ",
            attributes: [
                .font: NSFont(name: "IBMPlexSans-Regular", size: 13)
                    ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        let content = NSMutableAttributedString(
            attributedString: inlineAttributedString(
                in: item.contentRange,
                style: .body,
                document: document
            )
        )
        content.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: content.length))

        let result = NSMutableAttributedString(attributedString: prefix)
        result.append(content)
        return result
    }

    private func codeBlockAttributedString(
        _ codeBlock: MarkdownDocument.CodeBlock,
        document: MarkdownDocument
    ) -> NSAttributedString {
        let codeFont = NSFont(name: "IBMPlexMono-Regular", size: 12)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacingBefore = 8
        paragraphStyle.paragraphSpacing = 8

        let content = codeBlock.contentRange.map(document.text(in:)) ?? ""
        return NSAttributedString(
            string: content,
            attributes: [
                .font: codeFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle,
                .backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.5)
            ]
        )
    }

    private func baseAttributes(for style: InlineStyle) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        switch style {
        case .body:
            paragraphStyle.paragraphSpacing = 8
            return [
                .font: inlineFonts(for: style).regular,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle
            ]

        case .blockquote:
            paragraphStyle.paragraphSpacing = 4
            paragraphStyle.firstLineHeadIndent = 16
            paragraphStyle.headIndent = 16
            return [
                .font: inlineFonts(for: style).regular,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]

        case .heading(let level):
            paragraphStyle.paragraphSpacingBefore = level == 1 ? 12 : 8
            paragraphStyle.paragraphSpacing = 4
            return [
                .font: inlineFonts(for: style).regular,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle
            ]
        }
    }

    private func inlineFonts(for style: InlineStyle) -> (regular: NSFont, bold: NSFont, italic: NSFont, boldItalic: NSFont) {
        let regular: NSFont
        let bold: NSFont

        switch style {
        case .body, .blockquote:
            regular = NSFont(name: "IBMPlexSans-Regular", size: 13)
                ?? NSFont.systemFont(ofSize: 13)
            bold = NSFont(name: "IBMPlexSans-Medium", size: 13)
                ?? NSFont.boldSystemFont(ofSize: 13)

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
            regular = NSFont(name: "Newsreader-Medium", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .semibold)
            bold = NSFont(name: "Newsreader-SemiBold", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .bold)
        }

        let italic = NSFont(descriptor: regular.fontDescriptor.withSymbolicTraits(.italic), size: regular.pointSize) ?? regular
        let boldItalic = NSFont(descriptor: bold.fontDescriptor.withSymbolicTraits(.italic), size: bold.pointSize) ?? bold
        return (regular, bold, italic, boldItalic)
    }

    private func wikiLinkURL(for title: String) -> URL? {
        var components = URLComponents()
        components.scheme = "grove-wikilink"
        components.host = "item"
        components.queryItems = [URLQueryItem(name: "title", value: title)]
        return components.url
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectText: ((String) -> Void)?

        init(onSelectText: ((String) -> Void)?) {
            self.onSelectText = onSelectText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0,
               let text = textView.textStorage?.attributedSubstring(from: selectedRange).string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSelectText?(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
#else
/// iOS fallback: renders markdown as plain selectable text.
struct SelectableMarkdownView: View {
    let markdown: String
    var onSelectText: ((String) -> Void)?

    var body: some View {
        Text(markdown)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
