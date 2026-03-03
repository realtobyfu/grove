#if os(iOS)
import SwiftUI
import UIKit

/// UIViewRepresentable wrapping a HighlightingUITextView with live markdown
/// syntax highlighting, smart list/quote continuation, and wiki-link detection.
/// iOS counterpart of macOS `MarkdownNSTextView` (NSViewRepresentable).
struct MarkdownUITextView: UIViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var fontSize: CGFloat = 16
    var textInset: UIEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    var onWikiTrigger: ((String?) -> Void)?
    var editorProxy: MarkdownEditingProxy? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> HighlightingUITextView {
        let textView = HighlightingUITextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = textInset
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no

        let defaultFont = UIFont(name: "IBMPlexSans-Regular", size: fontSize)
            ?? UIFont.systemFont(ofSize: fontSize)
        textView.font = defaultFont
        textView.textColor = .label
        textView.showsMarkdownDecorations = true

        textView.typingAttributes = context.coordinator.baseTypingAttributes()

        // Set up formatting toolbar
        let accessoryView = MarkdownFormattingAccessoryView()
        accessoryView.formattingDelegate = textView
        textView.inputAccessoryView = accessoryView

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.registerEditorProxy()

        // Set initial text and apply highlighting
        textView.text = text
        context.coordinator.applyHighlighting(textView)

        return textView
    }

    func updateUIView(_ textView: HighlightingUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = textView
        context.coordinator.registerEditorProxy()

        textView.showsMarkdownDecorations = true

        if let accessoryView = textView.inputAccessoryView as? MarkdownFormattingAccessoryView {
            accessoryView.formattingDelegate = textView
        }

        if textView.text != text && !context.coordinator.isUpdating {
            let selectedRange = textView.selectedRange
            context.coordinator.beginProgrammaticUpdate()
            textView.text = text
            context.coordinator.applyHighlighting(textView)
            // Restore selection if still valid
            let maxLocation = (textView.text as NSString).length
            if selectedRange.location <= maxLocation {
                let clampedLength = min(selectedRange.length, maxLocation - selectedRange.location)
                textView.selectedRange = NSRange(location: min(selectedRange.location, maxLocation), length: clampedLength)
            }
            context.coordinator.endProgrammaticUpdate()
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownUITextView
        weak var textView: HighlightingUITextView?
        var isUpdating = false
        private var lastWikiQuery: String??

        init(_ parent: MarkdownUITextView) {
            self.parent = parent
        }

        func beginProgrammaticUpdate() {
            isUpdating = true
        }

        func endProgrammaticUpdate() {
            isUpdating = false
        }

        // MARK: - Text Changes

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            parent.text = textView.text
            applyHighlighting(textView)
            detectWikiLink(in: textView)
            isUpdating = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            applyHighlighting(textView)
            detectWikiLink(in: textView)
            textView.setNeedsDisplay()
            isUpdating = false
        }

        // MARK: - Smart Enter (List / Quote Continuation)

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }

            let nsText = textView.text as NSString
            let safeLocation = min(max(0, range.location), nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            let lineWithBreak = nsText.substring(with: lineRange)
            let line = lineWithBreak.trimmingCharacters(in: .newlines)

            if let listLine = parseListLine(line) {
                let isEmptyItem = listLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmptyItem {
                    // Empty list item — just insert newline (break out of list)
                    return true
                } else {
                    // Continue list
                    let insertion = "\n\(listLine.marker)\(listLine.spacer)"
                    let storage = textView.textStorage
                    isUpdating = true
                    storage.replaceCharacters(in: range, with: insertion)
                    textView.selectedRange = NSRange(location: range.location + (insertion as NSString).length, length: 0)
                    parent.text = textView.text
                    applyHighlighting(textView)
                    detectWikiLink(in: textView)
                    isUpdating = false
                    return false
                }
            }

            if let quoteLine = parseQuoteLine(line) {
                let isEmptyQuote = quoteLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmptyQuote {
                    return true
                } else {
                    let insertion = "\n>\(quoteLine.spacer)"
                    let storage = textView.textStorage
                    isUpdating = true
                    storage.replaceCharacters(in: range, with: insertion)
                    textView.selectedRange = NSRange(location: range.location + (insertion as NSString).length, length: 0)
                    parent.text = textView.text
                    applyHighlighting(textView)
                    detectWikiLink(in: textView)
                    isUpdating = false
                    return false
                }
            }

            return true
        }

        // MARK: - Wiki Link Detection

        private func detectWikiLink(in textView: UITextView) {
            let text = textView.text ?? ""
            let nsText = text as NSString
            let safeCursorLocation = min(max(0, textView.selectedRange.location), nsText.length)
            let prefix = nsText.substring(to: safeCursorLocation)
            let prefixNSString = prefix as NSString

            let openRange = prefixNSString.range(of: "[[", options: .backwards)
            guard openRange.location != NSNotFound else {
                emitWikiTrigger(nil)
                return
            }

            let queryStart = openRange.location + openRange.length
            guard queryStart <= prefixNSString.length else {
                emitWikiTrigger(nil)
                return
            }

            let query = prefixNSString.substring(from: queryStart)

            if query.contains("]]") || query.contains("\n") {
                emitWikiTrigger(nil)
                return
            }

            emitWikiTrigger(query)
        }

        private func emitWikiTrigger(_ query: String?) {
            guard lastWikiQuery != query else { return }
            lastWikiQuery = query
            parent.onWikiTrigger?(query)
        }

        // MARK: - Syntax Highlighting

        func applyHighlighting(_ textView: UITextView) {
            guard let textView = textView as? HighlightingUITextView else { return }
            let storage = textView.textStorage
            let text = storage.string
            let fullRange = NSRange(location: 0, length: storage.length)
            let selectedRange = textView.selectedRange
            let maxLocation = (text as NSString).length
            let clampedLocation = min(selectedRange.location, maxLocation)
            let clampedLength = min(selectedRange.length, max(0, maxLocation - clampedLocation))
            let selectionState = MarkdownDocument.SelectionState(
                range: clampedLocation..<(clampedLocation + clampedLength)
            )

            let defaultAttrs = baseTypingAttributes()
            textView.showsMarkdownDecorations = true

            storage.beginEditing()
            storage.setAttributedString(NSAttributedString(string: text, attributes: defaultAttrs))
            storage.removeAttribute(.groveListPrefix, range: fullRange)
            storage.removeAttribute(.groveQuotePrefix, range: fullRange)

            guard fullRange.length > 0 else {
                storage.endEditing()
                restoreSelectionIfNeeded(
                    NSRange(location: clampedLocation, length: clampedLength),
                    in: textView
                )
                textView.typingAttributes = defaultAttrs
                textView.setNeedsDisplay()
                return
            }

            applyLivePreview(in: storage, text: text, selectionState: selectionState)

            storage.endEditing()

            restoreSelectionIfNeeded(
                NSRange(location: clampedLocation, length: clampedLength),
                in: textView
            )
            textView.typingAttributes = defaultAttrs
            textView.setNeedsDisplay()
        }

        func registerEditorProxy() {
            parent.editorProxy?.update(
                .init(
                    wrapSelection: { [weak textView] prefix, suffix in
                        textView?.wrapSelectionWith(prefix: prefix, suffix: suffix)
                    },
                    insertPrefix: { [weak textView] prefix in
                        textView?.insertPrefixAtCurrentLine(prefix)
                    },
                    insertText: { [weak textView] text, cursorOffset in
                        textView?.insertTextAtSelection(text, cursorOffset: cursorOffset)
                    },
                    setHeading: { [weak textView] level in
                        textView?.setHeadingLevel(level)
                    },
                    toggleBlockQuote: { [weak textView] in
                        textView?.toggleLinePrefix("> ")
                    },
                    toggleListItem: { [weak textView] in
                        textView?.toggleLinePrefix("- ")
                    },
                    insertLink: { [weak textView] in
                        textView?.wrapSelectionWith(prefix: "[", suffix: "](url)")
                    },
                    insertWikiLink: { [weak textView] in
                        textView?.insertTextAtSelection("[[]]", cursorOffset: -2)
                    },
                    replaceActiveWikiQuery: { [weak textView] title in
                        textView?.replaceActiveWikiQuery(with: title)
                    }
                )
            )
        }

        func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont(),
                .foregroundColor: UIColor.label,
            ]
            if let paragraphStyle = proseParagraphStyle() {
                attributes[.paragraphStyle] = paragraphStyle
            }
            return attributes
        }

        private func applyLivePreview(
            in storage: NSTextStorage,
            text: String,
            selectionState: MarkdownDocument.SelectionState
        ) {
            let document = MarkdownDocument(text)
            let primaryColor = UIColor.label
            let secondaryColor = UIColor.secondaryLabel
            let tertiaryColor = UIColor.tertiaryLabel
            let codeBackground = UIColor.quaternaryLabel.withAlphaComponent(0.15)
            let hiddenDelimiterAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.clear,
                .font: UIFont.systemFont(ofSize: 0.1),
            ]
            let hiddenListPrefixAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.clear,
            ]
            let hiddenQuotePrefixAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.clear,
            ]

            for block in document.blocks {
                switch block.kind {
                case .heading(let heading):
                    let revealMarkers = document.shouldRevealHeading(heading, for: selectionState)
                    let markerAttrs = revealMarkers
                        ? [.font: bodyFont(), .foregroundColor: tertiaryColor]
                        : hiddenDelimiterAttrs
                    applyAttributes(markerAttrs, to: heading.markerRange, in: text, storage: storage)
                    applyAttributes(markerAttrs, to: heading.spacingRange, in: text, storage: storage)
                    applyAttributes(
                        [.paragraphStyle: headingParagraphStyle(for: heading.level)],
                        to: block.range,
                        in: text,
                        storage: storage
                    )
                    applyAttributes(
                        [
                            .font: headingFont(for: heading.level),
                            .foregroundColor: primaryColor,
                        ],
                        to: heading.contentRange,
                        in: text,
                        storage: storage
                    )

                case .blockquote(let blockquote):
                    for line in blockquote.lines {
                        let revealPrefix = document.shouldRevealPrefix(line.prefixRange, for: selectionState)
                        let prefixAttrs = revealPrefix
                            ? [.font: bodyFont(), .foregroundColor: tertiaryColor]
                            : hiddenQuotePrefixAttrs
                        applyAttributes(prefixAttrs, to: line.prefixRange, in: text, storage: storage)
                        applyAttributes([.groveQuotePrefix: true], to: line.prefixRange, in: text, storage: storage)
                        applyAttributes([.foregroundColor: secondaryColor], to: line.contentRange, in: text, storage: storage)
                        applyAttributes([.paragraphStyle: quoteParagraphStyle()], to: line.lineRange, in: text, storage: storage)
                    }

                case .bulletList(let list):
                    for item in list.items {
                        let revealPrefix = document.shouldRevealPrefix(item.prefixRange, for: selectionState)
                        let prefixAttrs = revealPrefix
                            ? [.font: bodyFont(), .foregroundColor: tertiaryColor]
                            : hiddenListPrefixAttrs
                        applyAttributes(prefixAttrs, to: item.prefixRange, in: text, storage: storage)
                        applyAttributes([.groveListPrefix: true], to: item.prefixRange, in: text, storage: storage)
                        applyAttributes([.foregroundColor: primaryColor], to: item.contentRange, in: text, storage: storage)
                        applyAttributes([.paragraphStyle: listParagraphStyle()], to: item.lineRange, in: text, storage: storage)
                    }

                case .codeBlock(let codeBlock):
                    let openingAttrs = document.shouldRevealCodeFence(codeBlock.openingFenceRange, for: selectionState)
                        ? [.foregroundColor: tertiaryColor, .font: monoFont()]
                        : hiddenDelimiterAttrs
                    applyAttributes(
                        openingAttrs,
                        to: codeBlock.openingFenceRange,
                        in: text,
                        storage: storage
                    )
                    if let closingFenceRange = codeBlock.closingFenceRange {
                        let closingAttrs = document.shouldRevealCodeFence(closingFenceRange, for: selectionState)
                            ? [.foregroundColor: tertiaryColor, .font: monoFont()]
                            : hiddenDelimiterAttrs
                        applyAttributes(
                            closingAttrs,
                            to: closingFenceRange,
                            in: text,
                            storage: storage
                        )
                    }
                    if let contentRange = codeBlock.contentRange {
                        applyAttributes(
                            [
                                .font: monoFont(),
                                .foregroundColor: primaryColor,
                                .backgroundColor: codeBackground,
                            ],
                            to: contentRange,
                            in: text,
                            storage: storage
                        )
                    }

                case .paragraph:
                    break
                }
            }

            for span in document.inlineSpans {
                let revealMarkers = document.shouldRevealInlineSpan(span, for: selectionState)
                let visibleMarkerAttrs = delimiterAttributes(
                    for: span.kind,
                    tertiaryColor: tertiaryColor,
                    codeBackground: codeBackground
                )
                let hiddenAttrs = hiddenDelimiterAttributes(
                    for: span.kind,
                    hiddenDelimiterAttrs: hiddenDelimiterAttrs
                )

                for markerRange in span.markerRanges {
                    applyAttributes(revealMarkers ? visibleMarkerAttrs : hiddenAttrs, to: markerRange, in: text, storage: storage)
                }

                guard let nsRange = nsRange(for: span.contentRange, in: text) else { continue }

                switch span.kind {
                case .bold:
                    applyFontTraits([.traitBold], to: nsRange, in: storage)
                case .italic:
                    applyFontTraits([.traitItalic], to: nsRange, in: storage)
                case .boldItalic:
                    applyFontTraits([.traitBold, .traitItalic], to: nsRange, in: storage)
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                case .inlineCode:
                    storage.addAttributes(
                        [
                            .font: monoFont(),
                            .backgroundColor: codeBackground,
                            .foregroundColor: primaryColor,
                        ],
                        range: nsRange
                    )
                case .wikiLink, .link:
                    storage.addAttributes(
                        [
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: secondaryColor,
                        ],
                        range: nsRange
                    )
                }
            }
        }

        private func delimiterAttributes(
            for kind: MarkdownDocument.InlineSpan.Kind,
            tertiaryColor: UIColor,
            codeBackground: UIColor
        ) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .inlineCode:
                return [
                    .font: monoFont(),
                    .foregroundColor: tertiaryColor,
                    .backgroundColor: codeBackground,
                ]
            default:
                return [
                    .font: bodyFont(),
                    .foregroundColor: tertiaryColor,
                ]
            }
        }

        private func hiddenDelimiterAttributes(
            for kind: MarkdownDocument.InlineSpan.Kind,
            hiddenDelimiterAttrs: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .inlineCode:
                return hiddenDelimiterAttrs.merging([.backgroundColor: UIColor.clear]) { _, new in new }
            default:
                return hiddenDelimiterAttrs
            }
        }

        private func applyAttributes(
            _ attributes: [NSAttributedString.Key: Any],
            to characterRange: Range<Int>,
            in text: String,
            storage: NSTextStorage
        ) {
            guard let nsRange = nsRange(for: characterRange, in: text), nsRange.length > 0 else { return }
            storage.addAttributes(attributes, range: nsRange)
        }

        private func nsRange(for characterRange: Range<Int>, in text: String) -> NSRange? {
            guard characterRange.lowerBound >= 0,
                  characterRange.upperBound >= characterRange.lowerBound,
                  characterRange.upperBound <= text.count else {
                return nil
            }

            let lower = text.index(text.startIndex, offsetBy: characterRange.lowerBound)
            let upper = text.index(text.startIndex, offsetBy: characterRange.upperBound)
            return NSRange(lower..<upper, in: text)
        }

        private func restoreSelectionIfNeeded(_ range: NSRange, in textView: UITextView) {
            guard textView.selectedRange != range else { return }
            textView.selectedRange = range
        }

        private func applyFontTraits(
            _ traits: UIFontDescriptor.SymbolicTraits,
            to nsRange: NSRange,
            in storage: NSTextStorage
        ) {
            storage.enumerateAttribute(.font, in: nsRange, options: []) { value, range, _ in
                let baseFont = (value as? UIFont) ?? self.bodyFont()
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(
                    baseFont.fontDescriptor.symbolicTraits.union(traits)
                ) ?? baseFont.fontDescriptor
                let font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
                storage.addAttribute(.font, value: font, range: range)
            }
        }

        private func bodyFont() -> UIFont {
            UIFont(name: "IBMPlexSans-Regular", size: parent.fontSize)
                ?? UIFont.systemFont(ofSize: parent.fontSize)
        }

        private func monoFont() -> UIFont {
            UIFont(name: "IBMPlexMono-Regular", size: parent.fontSize - 2)
                ?? UIFont.monospacedSystemFont(ofSize: parent.fontSize - 2, weight: .regular)
        }

        private func headingFont(for level: Int) -> UIFont {
            let size: CGFloat
            switch level {
            case 1:
                size = round(parent.fontSize * 1.55)
            case 2:
                size = round(parent.fontSize * 1.22)
            default:
                size = round(parent.fontSize * 1.08)
            }

            return UIFont(name: "Newsreader-Medium", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .medium)
        }

        private func proseParagraphStyle() -> NSMutableParagraphStyle? {
            guard parent.fontSize >= 17 else { return nil }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 6
            return style
        }

        private func baseParagraphStyle() -> NSParagraphStyle {
            proseParagraphStyle() ?? NSParagraphStyle.default
        }

        private func headingParagraphStyle(for level: Int) -> NSParagraphStyle {
            let style = (proseParagraphStyle() ?? NSMutableParagraphStyle())
            style.paragraphSpacingBefore = level == 1 ? 10 : 6
            style.paragraphSpacing = max(style.paragraphSpacing, 4)
            return style
        }

        private func quoteParagraphStyle() -> NSParagraphStyle {
            let style = (baseParagraphStyle().mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            let isProse = parent.fontSize >= 17
            let indent: CGFloat = isProse ? 14 : 11
            let markerAdvance: CGFloat = isProse ? 11 : 9
            style.firstLineHeadIndent = indent
            style.headIndent = indent + markerAdvance
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            return style
        }

        private func listParagraphStyle() -> NSParagraphStyle {
            let style = (baseParagraphStyle().mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            let isProse = parent.fontSize >= 17
            style.firstLineHeadIndent = 0
            style.headIndent = isProse ? 14 : 12
            style.paragraphSpacing = max(style.paragraphSpacing, isProse ? 8 : 6)
            return style
        }

        // MARK: - Line Parsing

        private func parseListLine(_ line: String) -> (marker: String, spacer: String, content: String)? {
            guard let first = line.first, first == "-" || first == "*" else { return nil }
            let afterMarker = line.dropFirst()
            guard !afterMarker.isEmpty else {
                return (String(first), " ", "")
            }

            let spacerPrefix = afterMarker.prefix { $0 == " " || $0 == "\t" }
            guard !spacerPrefix.isEmpty else { return nil }

            let spacer = String(spacerPrefix)
            let content = String(afterMarker.dropFirst(spacerPrefix.count))
            return (String(first), spacer, content)
        }

        private func parseQuoteLine(_ line: String) -> (spacer: String, content: String)? {
            guard line.first == ">" else { return nil }
            let afterMarker = line.dropFirst()
            let spacerPrefix = afterMarker.prefix { $0 == " " || $0 == "\t" }
            let spacer = spacerPrefix.isEmpty ? " " : String(spacerPrefix)
            let content = String(afterMarker.dropFirst(spacerPrefix.count))
            return (spacer, content)
        }
    }
}
#endif
