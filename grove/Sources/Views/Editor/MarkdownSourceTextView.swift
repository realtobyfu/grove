#if os(macOS)
import SwiftUI
import AppKit

struct MarkdownSourceTextView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var fontSize: CGFloat = 15
    var textInset: NSSize = NSSize(width: 8, height: 8)
    var onWikiTrigger: ((String?) -> Void)?
    var editorProxy: MarkdownEditingProxy?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = HighlightingTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = textInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let defaultFont = NSFont(name: "IBMPlexSans-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        var typingAttributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: NSColor.labelColor
        ]
        if fontSize >= 17 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            paragraphStyle.paragraphSpacing = 6
            typingAttributes[.paragraphStyle] = paragraphStyle
        }

        textView.font = defaultFont
        textView.typingAttributes = typingAttributes
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .limited
            textView.allowedWritingToolsResultOptions = [.plainText, .list]
        }

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.registerEditorProxy()

        scrollView.documentView = textView
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }
        context.coordinator.parent = self
        context.coordinator.textView = textView
        context.coordinator.registerEditorProxy()

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceTextView
        weak var textView: HighlightingTextView?
        private var isUpdating = false

        init(_ parent: MarkdownSourceTextView) {
            self.parent = parent
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

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            detectWikiLink(in: textView)
            isUpdating = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let selected = textView.selectedRange()
            guard selected.length == 0 else { return false }

            let nsText = textView.string as NSString
            let safeLocation = min(max(0, selected.location), nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

            if let listLine = parseListLine(line) {
                if listLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    textView.insertText("\n", replacementRange: selected)
                } else {
                    textView.insertText("\n\(listLine.marker)\(listLine.spacer)", replacementRange: selected)
                }
                return true
            }

            if let quoteLine = parseQuoteLine(line) {
                if quoteLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    textView.insertText("\n", replacementRange: selected)
                } else {
                    textView.insertText("\n>\(quoteLine.spacer)", replacementRange: selected)
                }
                return true
            }

            return false
        }

        private func detectWikiLink(in textView: NSTextView) {
            let text = textView.string
            let nsText = text as NSString
            let safeCursorLocation = min(max(0, textView.selectedRange().location), nsText.length)
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
