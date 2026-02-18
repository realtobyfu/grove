import SwiftUI
import SwiftData
import AppKit

// MARK: - RichMarkdownEditor

/// A rich text editor that stores markdown as the source of truth but renders
/// live formatting (bold, italic, code, headings, wiki-links) via NSTextView.
/// Includes a formatting toolbar and wiki-link autocomplete.
struct RichMarkdownEditor: View {
    @Binding var text: String
    var sourceItem: Item?
    var minHeight: CGFloat = 80
    var proseMode: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]

    @State private var showWikiPopover = false
    @State private var wikiSearchText = ""

    private var wikiSearchResults: [Item] {
        allItems.filter { candidate in
            if let sourceItem, candidate.id == sourceItem.id { return false }
            if wikiSearchText.isEmpty { return true }
            return candidate.title.localizedCaseInsensitiveContains(wikiSearchText)
        }.prefix(10).map { $0 }
    }

    var body: some View {
        if proseMode {
            VStack(spacing: 0) {
                MarkdownNSTextView(
                    text: $text,
                    minHeight: minHeight,
                    fontSize: 18,
                    textInset: NSSize(width: 40, height: 24),
                    onWikiTrigger: { searchText in
                        if let searchText {
                            wikiSearchText = searchText
                            showWikiPopover = true
                        } else {
                            showWikiPopover = false
                            wikiSearchText = ""
                        }
                    },
                    onInsertFormatting: nil
                )
                .frame(minHeight: minHeight)

                if showWikiPopover {
                    wikiLinkDropdown
                        .padding(.horizontal, 40)
                }

                proseToolbar
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Formatting toolbar
                formattingToolbar
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.borderInput, lineWidth: 1)
                    )
                    .padding(.bottom, 4)

                // Editor
                MarkdownNSTextView(
                    text: $text,
                    minHeight: minHeight,
                    onWikiTrigger: { searchText in
                        if let searchText {
                            wikiSearchText = searchText
                            showWikiPopover = true
                        } else {
                            showWikiPopover = false
                            wikiSearchText = ""
                        }
                    },
                    onInsertFormatting: nil
                )
                .frame(minHeight: minHeight)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderInput, lineWidth: 1)
                )

                // Wiki-link dropdown
                if showWikiPopover {
                    wikiLinkDropdown
                }
            }
        }
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            toolbarButton("Bold", icon: "bold", shortcut: "B") {
                wrapSelection(prefix: "**", suffix: "**")
            }
            toolbarButton("Italic", icon: "italic", shortcut: "I") {
                wrapSelection(prefix: "*", suffix: "*")
            }
            toolbarButton("Code", icon: "chevron.left.forwardslash.chevron.right", shortcut: "E") {
                wrapSelection(prefix: "`", suffix: "`")
            }
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)
            toolbarButton("Heading", icon: "number", shortcut: nil) {
                insertPrefix("# ")
            }
            toolbarButton("Link", icon: "link", shortcut: "K") {
                wrapSelection(prefix: "[", suffix: "](url)")
            }
            toolbarButton("Wiki Link", icon: "link.badge.plus", shortcut: nil) {
                insertText("[[]]", cursorOffset: -2)
            }
            Spacer()
        }
    }

    private func toolbarButton(_ label: String, icon: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textSecondary)
        .help(shortcut != nil ? "\(label) (\u{2318}\(shortcut!))" : label)
    }

    // MARK: - Prose Toolbar

    private var proseToolbar: some View {
        HStack(spacing: 16) {
            toolbarButton("Bold", icon: "bold", shortcut: "B") {
                wrapSelection(prefix: "**", suffix: "**")
            }
            toolbarButton("Italic", icon: "italic", shortcut: "I") {
                wrapSelection(prefix: "*", suffix: "*")
            }
            toolbarButton("Code", icon: "chevron.left.forwardslash.chevron.right", shortcut: "E") {
                wrapSelection(prefix: "`", suffix: "`")
            }
            toolbarButton("Link", icon: "link", shortcut: "K") {
                wrapSelection(prefix: "[", suffix: "](url)")
            }
            toolbarButton("Wiki Link", icon: "link.badge.plus", shortcut: nil) {
                insertText("[[]]", cursorOffset: -2)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
    }

    // MARK: - Toolbar Actions

    private func wrapSelection(prefix: String, suffix: String) {
        // Insert around cursor/selection — append to text if no selection info
        text += prefix + suffix
    }

    private func insertPrefix(_ prefix: String) {
        // Insert at beginning of current line or at cursor
        text += "\n" + prefix
    }

    private func insertText(_ insertion: String, cursorOffset: Int) {
        text += insertion
    }

    // MARK: - Wiki Link Dropdown

    private var wikiLinkDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "link")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                Text("Link to item")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button {
                    showWikiPopover = false
                    wikiSearchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveBadge)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            if wikiSearchResults.isEmpty {
                Text("No matching items")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(wikiSearchResults) { candidate in
                            Button {
                                insertWikiLink(for: candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: candidate.type.iconName)
                                        .font(.groveBadge)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 14)
                                    Text(candidate.title)
                                        .font(.groveBodySmall)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private func insertWikiLink(for target: Item) {
        // Replace the partial [[search with [[Item Title]]
        if let range = text.range(of: "[[", options: .backwards) {
            let before = text[text.startIndex..<range.lowerBound]
            text = before + "[[" + target.title + "]]"
        }

        // Auto-create connection
        if let sourceItem {
            let viewModel = ItemViewModel(modelContext: modelContext)
            let alreadyConnected = sourceItem.outgoingConnections.contains { $0.targetItem?.id == target.id }
                || sourceItem.incomingConnections.contains { $0.sourceItem?.id == target.id }
            if !alreadyConnected {
                _ = viewModel.createConnection(source: sourceItem, target: target, type: .related)
            }
        }

        showWikiPopover = false
        wikiSearchText = ""
    }
}

// MARK: - NSTextView Representable

/// NSViewRepresentable wrapping an NSTextView with live markdown syntax highlighting.
struct MarkdownNSTextView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var fontSize: CGFloat = 15
    var textInset: NSSize = NSSize(width: 8, height: 8)
    var onWikiTrigger: ((String?) -> Void)?
    var onInsertFormatting: ((String, String) -> Void)?

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

        // Set default font
        let defaultFont = NSFont(name: "IBMPlexSans-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

        // Build typing attributes — add generous line spacing for prose mode
        var typingAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: NSColor.labelColor
        ]
        if fontSize >= 17 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 8
            paragraphStyle.paragraphSpacing = 12
            typingAttrs[.paragraphStyle] = paragraphStyle
        }

        textView.font = defaultFont
        textView.typingAttributes = typingAttrs

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView

        // Set initial text
        textView.string = text
        context.coordinator.applyHighlighting(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyHighlighting(textView)
            textView.selectedRanges = selectedRanges
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNSTextView
        weak var textView: HighlightingTextView?
        private var isUpdating = false

        init(_ parent: MarkdownNSTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            applyHighlighting(textView)
            detectWikiLink(in: textView)
            isUpdating = false
        }

        // MARK: - Wiki Link Detection

        private func detectWikiLink(in textView: NSTextView) {
            let text = textView.string

            // Find the last [[ without a closing ]]
            guard let openRange = text.range(of: "[[", options: .backwards) else {
                parent.onWikiTrigger?(nil)
                return
            }

            let afterBrackets = text[openRange.upperBound...]

            // If we find ]], the link is closed
            if afterBrackets.contains("]]") {
                parent.onWikiTrigger?(nil)
                return
            }

            // Check cursor is after the [[
            let cursorLocation = textView.selectedRange().location
            let openLocation = text.distance(from: text.startIndex, to: openRange.lowerBound)
            if cursorLocation > openLocation {
                parent.onWikiTrigger?(String(afterBrackets))
            } else {
                parent.onWikiTrigger?(nil)
            }
        }

        // MARK: - Syntax Highlighting

        func applyHighlighting(_ textView: NSTextView) {
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            let text = storage.string

            let size = parent.fontSize
            let defaultFont = NSFont(name: "IBMPlexSans-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
            let monoFont = NSFont(name: "IBMPlexMono-Regular", size: size - 2) ?? NSFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
            let boldFont = NSFont(name: "IBMPlexSans-Medium", size: size) ?? NSFont.boldSystemFont(ofSize: size)
            let headingFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.55)) ?? NSFont.systemFont(ofSize: round(size * 1.55), weight: .medium)
            let headingSmallFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.22)) ?? NSFont.systemFont(ofSize: round(size * 1.22), weight: .medium)

            let primaryColor = NSColor.labelColor
            let secondaryColor = NSColor.secondaryLabelColor
            let tertiaryColor = NSColor.tertiaryLabelColor
            let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.15)

            // Build paragraph style for prose mode (generous line spacing)
            let proseParagraph: NSParagraphStyle? = {
                guard size >= 17 else { return nil }
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 8
                style.paragraphSpacing = 12
                return style
            }()

            storage.beginEditing()

            // Reset to default
            var defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: defaultFont,
                .foregroundColor: primaryColor
            ]
            if let proseParagraph {
                defaultAttrs[.paragraphStyle] = proseParagraph
            }
            storage.addAttributes(defaultAttrs, range: fullRange)

            // Bold: **text**
            applyPattern(
                #"\*\*(.+?)\*\*"#,
                in: text, storage: storage,
                contentAttributes: [.font: boldFont, .foregroundColor: primaryColor],
                delimiterAttributes: [.font: defaultFont, .foregroundColor: tertiaryColor]
            )

            // Italic: *text* (but not **)
            applyPattern(
                #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
                in: text, storage: storage,
                contentAttributes: [.obliqueness: 0.2 as NSNumber, .foregroundColor: primaryColor],
                delimiterAttributes: [.foregroundColor: tertiaryColor]
            )

            // Inline code: `text`
            applyPattern(
                #"`([^`]+)`"#,
                in: text, storage: storage,
                contentAttributes: [
                    .font: monoFont,
                    .backgroundColor: codeBackground,
                    .foregroundColor: primaryColor
                ],
                delimiterAttributes: [
                    .font: monoFont,
                    .foregroundColor: tertiaryColor,
                    .backgroundColor: codeBackground
                ]
            )

            // Headings: # at start of line
            applyLinePattern(
                #"^(#{1,2})\s+(.+)$"#,
                in: text, storage: storage,
                prefixAttributes: [.foregroundColor: tertiaryColor],
                contentAttributes: [.font: headingFont, .foregroundColor: primaryColor],
                smallContentAttributes: [.font: headingSmallFont, .foregroundColor: primaryColor]
            )

            // Wiki-links: [[text]]
            applyPattern(
                #"\[\[(.+?)\]\]"#,
                in: text, storage: storage,
                contentAttributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: secondaryColor
                ],
                delimiterAttributes: [.foregroundColor: tertiaryColor]
            )

            storage.endEditing()
        }

        /// Apply regex pattern with distinct styles for delimiters and content.
        private func applyPattern(
            _ pattern: String,
            in text: String,
            storage: NSTextStorage,
            contentAttributes: [NSAttributedString.Key: Any],
            delimiterAttributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }

                // Full match range — apply delimiter style
                storage.addAttributes(delimiterAttributes, range: match.range)

                // Group 1 (content) — apply content style on top
                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    if contentRange.location != NSNotFound {
                        storage.addAttributes(contentAttributes, range: contentRange)
                    }
                }
            }
        }

        /// Apply heading pattern — line-level with # prefix styling.
        private func applyLinePattern(
            _ pattern: String,
            in text: String,
            storage: NSTextStorage,
            prefixAttributes: [NSAttributedString.Key: Any],
            contentAttributes: [NSAttributedString.Key: Any],
            smallContentAttributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }

                let prefixRange = match.range(at: 1)
                let contentRange = match.range(at: 2)

                if prefixRange.location != NSNotFound {
                    storage.addAttributes(prefixAttributes, range: prefixRange)
                }

                if contentRange.location != NSNotFound {
                    // Use smaller font for ## headings
                    let prefix = nsText.substring(with: prefixRange)
                    let attrs = prefix.count >= 2 ? smallContentAttributes : contentAttributes
                    storage.addAttributes(attrs, range: contentRange)
                }
            }
        }

        // MARK: - Keyboard Shortcuts

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            false
        }
    }
}

// MARK: - HighlightingTextView

/// Custom NSTextView subclass that handles formatting keyboard shortcuts.
class HighlightingTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "b":
            wrapSelectionWith(prefix: "**", suffix: "**")
            return true
        case "i":
            wrapSelectionWith(prefix: "*", suffix: "*")
            return true
        case "e":
            wrapSelectionWith(prefix: "`", suffix: "`")
            return true
        case "k":
            wrapSelectionWith(prefix: "[", suffix: "](url)")
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func wrapSelectionWith(prefix: String, suffix: String) {
        let selectedRange = self.selectedRange()
        guard let textStorage = self.textStorage else { return }

        let selectedText: String
        if selectedRange.length > 0 {
            selectedText = (textStorage.string as NSString).substring(with: selectedRange)
        } else {
            selectedText = ""
        }

        let replacement = prefix + selectedText + suffix

        if shouldChangeText(in: selectedRange, replacementString: replacement) {
            textStorage.replaceCharacters(in: selectedRange, with: replacement)
            didChangeText()

            // Place cursor between prefix and suffix if no selection
            if selectedText.isEmpty {
                let cursorPos = selectedRange.location + prefix.count
                setSelectedRange(NSRange(location: cursorPos, length: 0))
            } else {
                // Select the wrapped content
                let newStart = selectedRange.location + prefix.count
                setSelectedRange(NSRange(location: newStart, length: selectedText.count))
            }
        }
    }
}
