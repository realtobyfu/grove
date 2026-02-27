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
              let storage = textView.textStorage,
              storage.length > 0 else { return nil }
        let width = proposal.width ?? 400
        let boundingRect = storage.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: width, height: ceil(boundingRect.height) + 8)
    }

    private func updateTextView(_ textView: NSTextView) {
        let attributed = markdownToAttributedString(markdown)
        textView.textStorage?.setAttributedString(attributed)
    }

    private func markdownToAttributedString(_ md: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = md.components(separatedBy: "\n")
        var i = 0

        let bodyFont = NSFont(name: "IBMPlexSans-Regular", size: 13)
            ?? NSFont.systemFont(ofSize: 13)
        let bodyColor = NSColor.textColor
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 4
        bodyParagraph.paragraphSpacing = 8

        while i < lines.count {
            let line = lines[i]

            // Code block
            if line.hasPrefix("```") {
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }

                let codeFont = NSFont(name: "IBMPlexMono", size: 12)
                    ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                let codeParagraph = NSMutableParagraphStyle()
                codeParagraph.lineSpacing = 2
                codeParagraph.paragraphSpacingBefore = 8
                codeParagraph.paragraphSpacing = 8

                let codeStr = NSAttributedString(string: codeLines.joined(separator: "\n") + "\n", attributes: [
                    .font: codeFont,
                    .foregroundColor: bodyColor,
                    .paragraphStyle: codeParagraph,
                    .backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.5)
                ])
                result.append(codeStr)
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level >= 1 && level <= 6 && !text.isEmpty {
                    let headingSize: CGFloat = level == 1 ? 22 : level == 2 ? 18 : level == 3 ? 16 : 14
                    let headingFont = NSFont(name: "Newsreader", size: headingSize)
                        ?? NSFont.systemFont(ofSize: headingSize, weight: .semibold)
                    let headingParagraph = NSMutableParagraphStyle()
                    headingParagraph.paragraphSpacingBefore = level == 1 ? 12 : 8
                    headingParagraph.paragraphSpacing = 4

                    let headingStr = NSAttributedString(string: text + "\n", attributes: [
                        .font: headingFont,
                        .foregroundColor: bodyColor,
                        .paragraphStyle: headingParagraph
                    ])
                    result.append(headingStr)
                    i += 1
                    continue
                }
            }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                var quoteLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">") {
                    quoteLines.append(lines[i].hasPrefix("> ") ? String(lines[i].dropFirst(2)) : "")
                    i += 1
                }
                let quoteParagraph = NSMutableParagraphStyle()
                quoteParagraph.lineSpacing = 4
                quoteParagraph.paragraphSpacing = 4
                quoteParagraph.headIndent = 16
                quoteParagraph.firstLineHeadIndent = 16

                for qLine in quoteLines {
                    let qTrimmed = qLine.trimmingCharacters(in: .whitespaces)
                    if qTrimmed.hasPrefix("- ") || qTrimmed.hasPrefix("* ") {
                        let bulletContent = qTrimmed.hasPrefix("- ") ? String(qTrimmed.dropFirst(2)) : String(qTrimmed.dropFirst(2))
                        let bulletPara = quoteParagraph.mutableCopy() as! NSMutableParagraphStyle
                        bulletPara.headIndent = 28
                        let itemStr = NSMutableAttributedString(string: "\u{2022} " + bulletContent + "\n", attributes: [
                            .font: bodyFont,
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: bulletPara
                        ])
                        applyInlineFormatting(itemStr, baseFont: bodyFont)
                        result.append(itemStr)
                    } else if !qTrimmed.isEmpty {
                        let itemStr = NSMutableAttributedString(string: qLine + "\n", attributes: [
                            .font: bodyFont,
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: quoteParagraph
                        ])
                        applyInlineFormatting(itemStr, baseFont: bodyFont)
                        result.append(itemStr)
                    }
                }
                continue
            }

            // Bullet list
            let trimmedForBullet = line.trimmingCharacters(in: .whitespaces)
            if trimmedForBullet.hasPrefix("- ") || trimmedForBullet.hasPrefix("* ") {
                var bulletItems: [(text: String, indent: Int)] = []
                while i < lines.count {
                    let current = lines[i]
                    let currentTrimmed = current.trimmingCharacters(in: .whitespaces)
                    let currentIndent = current.prefix(while: { $0 == " " || $0 == "\t" }).count
                    if currentTrimmed.hasPrefix("- ") {
                        bulletItems.append((String(currentTrimmed.dropFirst(2)), currentIndent))
                    } else if currentTrimmed.hasPrefix("* ") {
                        bulletItems.append((String(currentTrimmed.dropFirst(2)), currentIndent))
                    } else if currentTrimmed.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }

                for item in bulletItems {
                    let indentLevel = CGFloat(item.indent / 2)
                    let bulletIndent: CGFloat = indentLevel * 12
                    let bulletParagraph = NSMutableParagraphStyle()
                    bulletParagraph.lineSpacing = 4
                    bulletParagraph.paragraphSpacing = 4
                    bulletParagraph.headIndent = bulletIndent + 14
                    bulletParagraph.firstLineHeadIndent = bulletIndent

                    let itemStr = NSMutableAttributedString(string: "\u{2022} " + item.text + "\n", attributes: [
                        .font: bodyFont,
                        .foregroundColor: bodyColor,
                        .paragraphStyle: bulletParagraph
                    ])
                    applyInlineFormatting(itemStr, baseFont: bodyFont)
                    result.append(itemStr)
                }
                continue
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph
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

            let paragraphText = paragraphLines.joined(separator: "\n")
            let paraStr = NSMutableAttributedString(string: paragraphText + "\n", attributes: [
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: bodyParagraph
            ])
            applyInlineFormatting(paraStr, baseFont: bodyFont)
            result.append(paraStr)
        }

        return result
    }

    /// Apply inline markdown formatting (bold+italic, bold, italic, code) to an attributed string.
    private func applyInlineFormatting(_ attrStr: NSMutableAttributedString, baseFont: NSFont) {
        let mediumFont = NSFont(name: "IBMPlexSans-Medium", size: baseFont.pointSize)
            ?? NSFont.boldSystemFont(ofSize: baseFont.pointSize)
        let codeFont = NSFont(name: "IBMPlexMono-Regular", size: baseFont.pointSize - 1)
            ?? NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)

        // Bold+italic: ***text***
        let boldItalicFont = NSFont(descriptor: mediumFont.fontDescriptor.withSymbolicTraits(.italic),
                                    size: mediumFont.pointSize) ?? mediumFont
        replaceInlineMarker(in: attrStr, pattern: "\\*{3}(.+?)\\*{3}", font: boldItalicFont)
        replaceInlineMarker(in: attrStr, pattern: "_{3}(.+?)_{3}", font: boldItalicFont)

        // Bold: **text**
        replaceInlineMarker(in: attrStr, pattern: "\\*{2}(.+?)\\*{2}", font: mediumFont)
        replaceInlineMarker(in: attrStr, pattern: "_{2}(.+?)_{2}", font: mediumFont)

        // Italic: *text*
        let italicFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic),
                                size: baseFont.pointSize) ?? baseFont
        replaceInlineMarker(in: attrStr, pattern: "\\*(.+?)\\*", font: italicFont)
        replaceInlineMarker(in: attrStr, pattern: "(?<!\\w)_(.+?)_(?!\\w)", font: italicFont)

        // Inline code: `text`
        replaceInlineMarker(in: attrStr, pattern: "`([^`]+)`", font: codeFont, extraAttrs: [
            .backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.5)
        ])
    }

    private func replaceInlineMarker(
        in attrStr: NSMutableAttributedString,
        pattern: String,
        font: NSFont,
        extraAttrs: [NSAttributedString.Key: Any] = [:]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        while true {
            let text = attrStr.string
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)),
                  match.numberOfRanges >= 2 else { break }
            let fullRange = match.range
            let contentRange = match.range(at: 1)
            guard fullRange.location != NSNotFound, contentRange.location != NSNotFound else { break }

            let replacement = attrStr.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString
            let wholeRange = NSRange(location: 0, length: replacement.length)
            replacement.addAttribute(.font, value: font, range: wholeRange)
            for (key, value) in extraAttrs {
                replacement.addAttribute(key, value: value, range: wholeRange)
            }
            attrStr.replaceCharacters(in: fullRange, with: replacement)
        }
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
