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
            return candidate.title.localizedStandardContains(wikiSearchText)
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
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Menu {
                Button("# Title") { insertPrefix("# ") }
                Button("## Heading") { insertPrefix("## ") }
                Button("### Subheading") { insertPrefix("### ") }
            } label: {
                Image(systemName: "number")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .help("Heading")

            toolbarButton("List", icon: "list.bullet", shortcut: nil) {
                insertPrefix("- ")
            }
            toolbarButton("Quote", icon: "text.quote", shortcut: nil) {
                insertPrefix("> ")
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Menu {
                Button("Code") { wrapSelection(prefix: "`", suffix: "`") }
                Button("Link") { wrapSelection(prefix: "[", suffix: "](url)") }
                Button("Wiki Link") { insertText("[[]]", cursorOffset: -2) }
                Divider()
                Button("Strikethrough") { wrapSelection(prefix: "~~", suffix: "~~") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .help("More")
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

            Menu {
                Button("# Title") { insertPrefix("# ") }
                Button("## Heading") { insertPrefix("## ") }
                Button("### Subheading") { insertPrefix("### ") }
            } label: {
                Image(systemName: "number")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .help("Heading")

            toolbarButton("List", icon: "list.bullet", shortcut: nil) {
                insertPrefix("- ")
            }
            toolbarButton("Quote", icon: "text.quote", shortcut: nil) {
                insertPrefix("> ")
            }

            Menu {
                Button("Code") { wrapSelection(prefix: "`", suffix: "`") }
                Button("Link") { wrapSelection(prefix: "[", suffix: "](url)") }
                Button("Wiki Link") { insertText("[[]]", cursorOffset: -2) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .help("More")

            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
    }

    // MARK: - Toolbar Actions

    private func withFocusedEditor(_ action: (HighlightingTextView) -> Void, fallback: () -> Void) {
        if let focusedEditor = HighlightingTextView.focusedEditor {
            action(focusedEditor)
        } else {
            fallback()
        }
    }

    private func wrapSelection(prefix: String, suffix: String) {
        withFocusedEditor(
            { $0.wrapSelectionWith(prefix: prefix, suffix: suffix) },
            fallback: { text += prefix + suffix }
        )
    }

    private func insertPrefix(_ prefix: String) {
        withFocusedEditor(
            { $0.insertPrefixAtCurrentLine(prefix) },
            fallback: { text += "\n" + prefix }
        )
    }

    private func insertText(_ insertion: String, cursorOffset: Int) {
        withFocusedEditor(
            { $0.insertTextAtSelection(insertion, cursorOffset: cursorOffset) },
            fallback: { text += insertion }
        )
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
        if let focusedEditor = HighlightingTextView.focusedEditor {
            focusedEditor.replaceActiveWikiQuery(with: target.title)
        } else if let range = text.range(of: "[[", options: .backwards) {
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
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .limited
            textView.allowedWritingToolsResultOptions = [.plainText, .list]
        }

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

    @MainActor
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

        // MARK: - Syntax Highlighting

        func applyHighlighting(_ textView: NSTextView) {
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            let text = storage.string
            let cursorLocation = min(max(0, textView.selectedRange().location), (text as NSString).length)

            let size = parent.fontSize
            let defaultFont = NSFont(name: "IBMPlexSans-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
            let monoFont = NSFont(name: "IBMPlexMono-Regular", size: size - 2) ?? NSFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
            let boldFont = NSFont(name: "IBMPlexSans-Medium", size: size) ?? NSFont.boldSystemFont(ofSize: size)
            let headingFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.55)) ?? NSFont.systemFont(ofSize: round(size * 1.55), weight: .medium)
            let headingSmallFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.22)) ?? NSFont.systemFont(ofSize: round(size * 1.22), weight: .medium)
            let headingMidFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.08)) ?? NSFont.systemFont(ofSize: round(size * 1.08), weight: .medium)
            let quoteFontSize = size + (size >= 17 ? 1.5 : 1)
            let fallbackQuoteFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: quoteFontSize),
                toHaveTrait: .italicFontMask
            )
            let quoteFont = NSFont(name: "Newsreader-Italic", size: quoteFontSize) ?? fallbackQuoteFont
            let quoteColor = NSColor.labelColor.withAlphaComponent(0.92)

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

            let hiddenDelimiterAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.1)
            ]
            let hiddenListPrefixAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear
            ]

            // Bold + italic: ***text***
            applyPattern(
                #"\*\*\*(.+?)\*\*\*"#,
                in: text, storage: storage,
                contentAttributes: [
                    .font: boldFont,
                    .obliqueness: 0.2 as NSNumber,
                    .foregroundColor: primaryColor
                ],
                delimiterAttributes: [.font: defaultFont, .foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Bold: **text**
            applyPattern(
                #"\*\*(.+?)\*\*"#,
                in: text, storage: storage,
                contentAttributes: [.font: boldFont, .foregroundColor: primaryColor],
                delimiterAttributes: [.font: defaultFont, .foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            // Italic: *text* (but not **)
            applyPattern(
                #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
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
                    .foregroundColor: primaryColor
                ],
                delimiterAttributes: [
                    .font: monoFont,
                    .foregroundColor: tertiaryColor,
                    .backgroundColor: codeBackground
                ],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs.merging([.backgroundColor: NSColor.clear]) { _, new in new },
                cursorLocation: cursorLocation
            )

            // Headings: #, ##, ###, ####... at start of line
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
                #"^(>\s?)(.*)$"#,
                in: text,
                storage: storage,
                cursorLocation: cursorLocation,
                prefixAttributes: [.foregroundColor: tertiaryColor],
                hiddenPrefixAttributes: hiddenDelimiterAttrs,
                contentAttributes: [
                    .font: quoteFont,
                    .foregroundColor: quoteColor
                ],
                lineTransform: { style, _ in
                    self.quoteParagraphStyle(from: style, isProse: proseParagraph != nil)
                }
            )

            // List item: - item
            applyPrefixLinePattern(
                #"^([-\*]\s+)(.*)$"#,
                in: text,
                storage: storage,
                cursorLocation: cursorLocation,
                prefixAttributes: [.foregroundColor: tertiaryColor],
                hiddenPrefixAttributes: hiddenListPrefixAttrs,
                contentAttributes: [.foregroundColor: primaryColor],
                lineTransform: { style, isEditingPrefix in
                    self.listParagraphStyle(
                        from: style,
                        isProse: proseParagraph != nil,
                        showVisualMarker: !isEditingPrefix
                    )
                }
            )

            // Wiki-links: [[text]]
            applyPattern(
                #"\[\[(.+?)\]\]"#,
                in: text, storage: storage,
                contentAttributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: secondaryColor
                ],
                delimiterAttributes: [.foregroundColor: tertiaryColor],
                hiddenDelimiterAttributes: hiddenDelimiterAttrs,
                cursorLocation: cursorLocation
            )

            storage.endEditing()
        }

        /// Apply regex pattern with distinct styles for delimiters and content.
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

                // Full match range — apply delimiter style or hide tokens when cursor is elsewhere
                storage.addAttributes(isEditingMatch ? delimiterAttributes : hiddenDelimiterAttributes, range: match.range)

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

                // Keep heading paragraph spacing even for empty heading lines.
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
            lineTransform: (NSParagraphStyle, Bool) -> NSParagraphStyle
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }

                let prefixRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let lineRange = match.range
                let isEditingPrefix = prefixRange.location != NSNotFound && self.rangeContainsCursor(prefixRange, cursorLocation: cursorLocation)
                let effectivePrefixAttrs = isEditingPrefix ? prefixAttributes : hiddenPrefixAttributes

                if prefixRange.location != NSNotFound {
                    storage.addAttributes(effectivePrefixAttrs, range: prefixRange)
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

        private func quoteParagraphStyle(from baseStyle: NSParagraphStyle, isProse: Bool) -> NSParagraphStyle {
            let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            let block = NSTextBlock()
            let accent = NSColor.controlAccentColor

            block.backgroundColor = accent.withAlphaComponent(isProse ? 0.12 : 0.1)
            block.setBorderColor(accent.withAlphaComponent(0.7), for: .minX)
            let panelBorder = accent.withAlphaComponent(0.22)
            block.setBorderColor(panelBorder, for: .maxX)
            block.setBorderColor(panelBorder, for: .minY)
            block.setBorderColor(panelBorder, for: .maxY)

            let railWidth: CGFloat = isProse ? 3.4 : 3.0
            block.setWidth(railWidth, type: .absoluteValueType, for: .border, edge: .minX)
            block.setWidth(0.7, type: .absoluteValueType, for: .border, edge: .maxX)
            block.setWidth(0.7, type: .absoluteValueType, for: .border, edge: .minY)
            block.setWidth(0.7, type: .absoluteValueType, for: .border, edge: .maxY)

            let leftPadding: CGFloat = isProse ? 14 : 11
            let rightPadding: CGFloat = isProse ? 12 : 10
            block.setWidth(leftPadding, type: .absoluteValueType, for: .padding, edge: .minX)
            block.setWidth(rightPadding, type: .absoluteValueType, for: .padding, edge: .maxX)
            block.setWidth(isProse ? 6 : 5, type: .absoluteValueType, for: .padding, edge: .minY)
            block.setWidth(isProse ? 7 : 6, type: .absoluteValueType, for: .padding, edge: .maxY)
            block.setWidth(0, type: .absoluteValueType, for: .margin)

            style.textBlocks = [block]
            style.firstLineHeadIndent = 0
            style.headIndent = 0
            style.paragraphSpacing = max(style.paragraphSpacing, isProse ? 12 : 9)
            style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, isProse ? 6 : 4)
            return style
        }

        private func listParagraphStyle(from baseStyle: NSParagraphStyle, isProse: Bool, showVisualMarker: Bool) -> NSParagraphStyle {
            let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            if showVisualMarker {
                style.textLists = [NSTextList(markerFormat: .circle, options: 0)]
                style.firstLineHeadIndent = 0
                style.headIndent = isProse ? 14 : 12
            } else {
                style.textLists = []
                style.firstLineHeadIndent = 0
                style.headIndent = 0
            }
            style.paragraphSpacing = max(style.paragraphSpacing, isProse ? 8 : 6)
            return style
        }

        // MARK: - Keyboard Shortcuts

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let selected = textView.selectedRange()
            guard selected.length == 0 else { return false }
            let nsText = textView.string as NSString
            let safeLocation = min(max(0, selected.location), nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            let line = nsText.substring(with: lineRange)

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let marker: String = line.hasPrefix("* ") ? "*" : "-"
                if line.trimmingCharacters(in: .whitespacesAndNewlines) == marker {
                    textView.insertText("\n", replacementRange: selected)
                } else {
                    textView.insertText("\n\(marker) ", replacementRange: selected)
                }
                return true
            }
            if line.hasPrefix("> ") || line == ">" {
                if line.trimmingCharacters(in: .whitespacesAndNewlines) == ">" {
                    textView.insertText("\n", replacementRange: selected)
                } else {
                    textView.insertText("\n> ", replacementRange: selected)
                }
                return true
            }
            return false
        }
    }
}

// MARK: - HighlightingTextView

/// Custom NSTextView subclass that handles formatting keyboard shortcuts.
class HighlightingTextView: NSTextView {
    static weak var focusedEditor: HighlightingTextView?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            Self.focusedEditor = self
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        if Self.focusedEditor === self {
            Self.focusedEditor = nil
        }
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let hasFormattingModifier = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        guard hasFormattingModifier else {
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

    func wrapSelectionWith(prefix: String, suffix: String) {
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

    func insertTextAtSelection(_ insertion: String, cursorOffset: Int = 0) {
        let selectedRange = selectedRange()
        guard let textStorage = textStorage else { return }
        let insertedLength = (insertion as NSString).length

        if shouldChangeText(in: selectedRange, replacementString: insertion) {
            textStorage.replaceCharacters(in: selectedRange, with: insertion)
            didChangeText()
            let minCursor = selectedRange.location
            let maxCursor = selectedRange.location + insertedLength
            let proposed = maxCursor + cursorOffset
            let clamped = min(max(proposed, minCursor), maxCursor)
            setSelectedRange(NSRange(location: clamped, length: 0))
        }
    }

    func insertPrefixAtCurrentLine(_ prefix: String) {
        let selectedRange = selectedRange()
        let nsText = string as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let insertionRange = NSRange(location: lineRange.location, length: 0)
        guard let textStorage = textStorage else { return }
        let prefixLength = (prefix as NSString).length

        if shouldChangeText(in: insertionRange, replacementString: prefix) {
            textStorage.replaceCharacters(in: insertionRange, with: prefix)
            didChangeText()
            let shiftedCursor = selectedRange.location + prefixLength
            setSelectedRange(NSRange(location: shiftedCursor, length: selectedRange.length))
        }
    }

    func replaceActiveWikiQuery(with title: String) {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0 else { return }

        let nsText = string as NSString
        let safeCursor = min(selectedRange.location, nsText.length)
        let prefix = nsText.substring(to: safeCursor)
        let prefixNSString = prefix as NSString
        let openRange = prefixNSString.range(of: "[[", options: .backwards)
        guard openRange.location != NSNotFound else { return }

        let queryStart = openRange.location + openRange.length
        let query = prefixNSString.substring(from: queryStart)
        guard !query.contains("]]"), !query.contains("\n") else { return }

        let replacementRange = NSRange(location: openRange.location, length: safeCursor - openRange.location)
        let replacement = "[[\(title)]]"
        guard let textStorage = textStorage else { return }
        let replacementLength = (replacement as NSString).length

        if shouldChangeText(in: replacementRange, replacementString: replacement) {
            textStorage.replaceCharacters(in: replacementRange, with: replacement)
            didChangeText()
            let cursor = replacementRange.location + replacementLength
            setSelectedRange(NSRange(location: cursor, length: 0))
        }
    }
}
