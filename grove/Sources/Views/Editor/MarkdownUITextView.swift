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

        var typingAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: UIColor.label,
        ]
        if fontSize >= 17 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            paragraphStyle.paragraphSpacing = 6
            typingAttrs[.paragraphStyle] = paragraphStyle
        }
        textView.typingAttributes = typingAttrs

        // Set up formatting toolbar
        let accessoryView = MarkdownFormattingAccessoryView()
        accessoryView.formattingDelegate = textView
        textView.inputAccessoryView = accessoryView

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Set initial text and apply highlighting
        textView.text = text
        context.coordinator.applyHighlighting(textView)

        return textView
    }

    func updateUIView(_ textView: HighlightingUITextView, context: Context) {
        if textView.text != text && !context.coordinator.isUpdating {
            let selectedRange = textView.selectedRange
            textView.text = text
            context.coordinator.applyHighlighting(textView)
            // Restore selection if still valid
            let maxLocation = (textView.text as NSString).length
            if selectedRange.location <= maxLocation {
                let clampedLength = min(selectedRange.length, maxLocation - selectedRange.location)
                textView.selectedRange = NSRange(location: min(selectedRange.location, maxLocation), length: clampedLength)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownUITextView
        weak var textView: HighlightingUITextView?
        var isUpdating = false

        init(_ parent: MarkdownUITextView) {
            self.parent = parent
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
                parent.onWikiTrigger?(nil)
                return
            }

            let queryStart = openRange.location + openRange.length
            guard queryStart <= prefixNSString.length else {
                parent.onWikiTrigger?(nil)
                return
            }

            let query = prefixNSString.substring(from: queryStart)

            if query.contains("]]") || query.contains("\n") {
                parent.onWikiTrigger?(nil)
                return
            }

            parent.onWikiTrigger?(query)
        }

        // MARK: - Syntax Highlighting

        func applyHighlighting(_ textView: UITextView) {
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }
            let text = storage.string
            let cursorLocation = min(max(0, textView.selectedRange.location), (text as NSString).length)

            let size = parent.fontSize
            let defaultFont = UIFont(name: "IBMPlexSans-Regular", size: size)
                ?? UIFont.systemFont(ofSize: size)
            let monoFont = UIFont(name: "IBMPlexMono-Regular", size: size - 2)
                ?? UIFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
            let boldFont = UIFont(name: "IBMPlexSans-Medium", size: size)
                ?? UIFont.boldSystemFont(ofSize: size)
            let headingFont = UIFont(name: "Newsreader-Medium", size: round(size * 1.55))
                ?? UIFont.systemFont(ofSize: round(size * 1.55), weight: .medium)
            let headingSmallFont = UIFont(name: "Newsreader-Medium", size: round(size * 1.22))
                ?? UIFont.systemFont(ofSize: round(size * 1.22), weight: .medium)
            let headingMidFont = UIFont(name: "Newsreader-Medium", size: round(size * 1.08))
                ?? UIFont.systemFont(ofSize: round(size * 1.08), weight: .medium)
            let quoteColor = UIColor.label.withAlphaComponent(0.92)

            let primaryColor = UIColor.label
            let secondaryColor = UIColor.secondaryLabel
            let tertiaryColor = UIColor.tertiaryLabel
            let codeBackground = UIColor.quaternaryLabel.withAlphaComponent(0.15)

            let proseParagraph: NSParagraphStyle? = {
                guard size >= 17 else { return nil }
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacing = 6
                return style
            }()

            storage.beginEditing()
            storage.removeAttribute(.groveListPrefix, range: fullRange)
            storage.removeAttribute(.groveQuotePrefix, range: fullRange)

            // Reset to default
            var defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: defaultFont,
                .foregroundColor: primaryColor,
            ]
            if let proseParagraph {
                defaultAttrs[.paragraphStyle] = proseParagraph
            }
            storage.addAttributes(defaultAttrs, range: fullRange)

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

            // Bold + italic: ***text***
            applyPattern(
                #"\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*"#,
                in: text, storage: storage,
                contentAttributes: [
                    .font: boldFont,
                    .obliqueness: 0.2 as NSNumber,
                    .foregroundColor: primaryColor,
                ],
                delimiterAttributes: [.font: defaultFont, .foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Bold: **text**
            applyPattern(
                #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#,
                in: text, storage: storage,
                contentAttributes: [.font: boldFont, .foregroundColor: primaryColor],
                delimiterAttributes: [.font: defaultFont, .foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Italic: *text* (but not **)
            applyPattern(
                #"(?<!\*)\*(?!\*)(?=\S)(.+?)(?<=\S)(?<!\*)\*(?!\*)"#,
                in: text, storage: storage,
                contentAttributes: [.obliqueness: 0.2 as NSNumber, .foregroundColor: primaryColor],
                delimiterAttributes: [.foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Inline code: `text`
            applyPattern(
                #"`([^`]+)`"#,
                in: text, storage: storage,
                contentAttributes: [
                    .font: monoFont,
                    .backgroundColor: codeBackground,
                    .foregroundColor: primaryColor,
                ],
                delimiterAttributes: [
                    .font: monoFont,
                    .foregroundColor: tertiaryColor,
                    .backgroundColor: codeBackground,
                ],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs.merging([.backgroundColor: UIColor.clear]) { _, new in new },
                cursorLocation: cursorLocation
            )

            // Markdown links: [text](url)
            applyPattern(
                #"\[(?!\[)(.+?)\]\((.+?)\)"#,
                in: text, storage: storage,
                contentAttributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: secondaryColor,
                ],
                delimiterAttributes: [.foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Strikethrough: ~~text~~
            applyPattern(
                #"~~(?=\S)(.+?)(?<=\S)~~"#,
                in: text, storage: storage,
                contentAttributes: [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: secondaryColor,
                ],
                delimiterAttributes: [.foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Headings: #, ##, ### at start of line
            applyHeadingLinePattern(
                in: text,
                storage: storage,
                cursorLocation: cursorLocation,
                prefixAttributes: [.foregroundColor: tertiaryColor],
                hiddenPrefixAttributes: hiddenDelimiterAttrs,
                h1Attributes: [.font: headingFont, .foregroundColor: primaryColor],
                h2Attributes: [.font: headingSmallFont, .foregroundColor: primaryColor],
                h3Attributes: [.font: headingMidFont, .foregroundColor: primaryColor],
                proseParagraph: proseParagraph
            )

            // Block quote: > text
            applyPrefixLinePattern(
                #"^(>[ \t]*)(.*)$"#,
                in: text,
                storage: storage,
                cursorLocation: cursorLocation,
                prefixAttributes: [.foregroundColor: tertiaryColor],
                hiddenPrefixAttributes: hiddenQuotePrefixAttrs,
                contentAttributes: [
                    .font: defaultFont,
                    .foregroundColor: quoteColor,
                ],
                prefixMarkerAttributes: [.groveQuotePrefix: true],
                lineTransform: { style, _ in
                    self.quoteParagraphStyle(from: style)
                }
            )

            // List item: - item or * item
            applyPrefixLinePattern(
                #"^([-\*]\s+)(.*)$"#,
                in: text,
                storage: storage,
                cursorLocation: cursorLocation,
                prefixAttributes: [.foregroundColor: tertiaryColor],
                hiddenPrefixAttributes: hiddenListPrefixAttrs,
                contentAttributes: [.foregroundColor: primaryColor],
                prefixMarkerAttributes: [.groveListPrefix: true],
                lineTransform: { style, _ in
                    self.listParagraphStyle(from: style)
                }
            )

            // Wiki-links: [[text]]
            applyPattern(
                #"\[\[(.+?)\]\]"#,
                in: text, storage: storage,
                contentAttributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: secondaryColor,
                ],
                delimiterAttributes: [.foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            storage.endEditing()
        }

        // MARK: - Pattern Helpers

        private func applyPattern(
            _ pattern: String,
            in text: String,
            storage: NSTextStorage,
            contentAttributes: [NSAttributedString.Key: Any],
            delimiterAttributes: [NSAttributedString.Key: Any],
            hiddenDelimiterAttributes: [NSAttributedString.Key: Any],
            cursorLocation: Int
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                let isEditingMatch = self.rangeContainsCursor(match.range, cursorLocation: cursorLocation)
                let tokenAttributes = isEditingMatch ? delimiterAttributes : hiddenDelimiterAttributes

                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    if contentRange.location != NSNotFound {
                        let matchStart = match.range.location
                        let matchEnd = match.range.location + match.range.length
                        let contentStart = contentRange.location
                        let contentEnd = contentRange.location + contentRange.length

                        if contentStart > matchStart {
                            storage.addAttributes(
                                tokenAttributes,
                                range: NSRange(location: matchStart, length: contentStart - matchStart)
                            )
                        }
                        if contentEnd < matchEnd {
                            storage.addAttributes(
                                tokenAttributes,
                                range: NSRange(location: contentEnd, length: matchEnd - contentEnd)
                            )
                        }

                        storage.addAttributes(contentAttributes, range: contentRange)
                        return
                    }
                }

                storage.addAttributes(tokenAttributes, range: match.range)
            }
        }

        private func applyHeadingLinePattern(
            in text: String,
            storage: NSTextStorage,
            cursorLocation: Int,
            prefixAttributes: [NSAttributedString.Key: Any],
            hiddenPrefixAttributes: [NSAttributedString.Key: Any],
            h1Attributes: [NSAttributedString.Key: Any],
            h2Attributes: [NSAttributedString.Key: Any],
            h3Attributes: [NSAttributedString.Key: Any],
            proseParagraph: NSParagraphStyle?
        ) {
            guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})(\s*)(.*)$"#, options: [.anchorsMatchLines]) else { return }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 4 else { return }

                let prefixRange = match.range(at: 1)
                let spacingRange = match.range(at: 2)
                let contentRange = match.range(at: 3)
                let isEditingLine = self.rangeContainsCursor(match.range, cursorLocation: cursorLocation)
                let effectivePrefixAttrs = isEditingLine ? prefixAttributes : hiddenPrefixAttributes

                if prefixRange.location != NSNotFound {
                    storage.addAttributes(effectivePrefixAttrs, range: prefixRange)
                }
                if spacingRange.location != NSNotFound {
                    storage.addAttributes(effectivePrefixAttrs, range: spacingRange)
                }

                guard contentRange.location != NSNotFound else { return }
                let prefix = nsText.substring(with: prefixRange)
                let level = prefix.count
                let contentAttrs: [NSAttributedString.Key: Any]
                switch level {
                case 1, 4, 5, 6: contentAttrs = h1Attributes
                case 2: contentAttrs = h2Attributes
                default: contentAttrs = h3Attributes
                }
                storage.addAttributes(contentAttrs, range: contentRange)

                if let proseParagraph {
                    storage.addAttribute(.paragraphStyle, value: proseParagraph, range: match.range)
                }
            }
        }

        private func applyPrefixLinePattern(
            _ pattern: String,
            in text: String,
            storage: NSTextStorage,
            cursorLocation: Int,
            prefixAttributes: [NSAttributedString.Key: Any],
            hiddenPrefixAttributes: [NSAttributedString.Key: Any],
            contentAttributes: [NSAttributedString.Key: Any],
            prefixMarkerAttributes: [NSAttributedString.Key: Any] = [:],
            lineTransform: (NSParagraphStyle, Bool) -> NSParagraphStyle
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }

                let prefixRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let lineRange = match.range
                let isEditingPrefix = prefixRange.location != NSNotFound
                    && cursorLocation >= prefixRange.location
                    && cursorLocation <= (prefixRange.location + prefixRange.length)
                let effectivePrefixAttrs = isEditingPrefix ? prefixAttributes : hiddenPrefixAttributes

                if prefixRange.location != NSNotFound {
                    storage.addAttributes(effectivePrefixAttrs, range: prefixRange)
                    if !prefixMarkerAttributes.isEmpty {
                        storage.addAttributes(prefixMarkerAttributes, range: prefixRange)
                    }
                }
                if contentRange.location != NSNotFound {
                    storage.addAttributes(contentAttributes, range: contentRange)
                }

                let existingStyle = (storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)
                    ?? NSParagraphStyle.default
                let updatedStyle = lineTransform(existingStyle, isEditingPrefix)
                storage.addAttribute(.paragraphStyle, value: updatedStyle, range: lineRange)
            }
        }

        private func rangeContainsCursor(_ range: NSRange, cursorLocation: Int) -> Bool {
            if range.location == NSNotFound { return false }
            let upperBound = range.location + range.length
            return cursorLocation >= range.location && cursorLocation <= upperBound
        }

        // MARK: - Paragraph Styles

        private func quoteParagraphStyle(from baseStyle: NSParagraphStyle) -> NSParagraphStyle {
            let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            let indent: CGFloat = 11
            let markerAdvance: CGFloat = 9
            style.firstLineHeadIndent = indent
            style.headIndent = indent + markerAdvance
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            return style
        }

        private func listParagraphStyle(from baseStyle: NSParagraphStyle) -> NSParagraphStyle {
            let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            style.firstLineHeadIndent = 0
            style.headIndent = 12
            style.paragraphSpacing = max(style.paragraphSpacing, 6)
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
