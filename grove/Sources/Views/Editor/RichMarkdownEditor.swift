#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

private extension NSAttributedString.Key {
    static let groveListPrefix = NSAttributedString.Key("groveListPrefix")
    static let groveQuotePrefix = NSAttributedString.Key("groveQuotePrefix")
}

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

    @State private var editingProxy = MarkdownEditingProxy()
    @State private var showWikiPopover = false
    @State private var wikiSearchText = ""

    private var wikiSearchResults: [Item] {
        allItems.filter { candidate in
            if let sourceItem, candidate.id == sourceItem.id { return false }
            if wikiSearchText.isEmpty { return true }
            return candidate.title.localizedStandardContains(wikiSearchText)
        }.prefix(10).map { $0 }
    }

    private var wordCountLabel: String {
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        return "\(wordCount) \(wordCount == 1 ? "Word" : "Words")"
    }

    var body: some View {
        Group {
            if proseMode {
                VStack(spacing: 0) {
                    editorContent
                    if showWikiPopover {
                        wikiLinkDropdown
                            .padding(.horizontal, 40)
                    }
                    proseToolbar
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
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

                    editorContent
                        .frame(minHeight: minHeight)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.borderInput, lineWidth: 1)
                        )

                    if showWikiPopover {
                        wikiLinkDropdown
                    }
                }
            }
        }
        .onDisappear {
            editingProxy.clear()
        }
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            toolbarButton("Bold", icon: "bold", shortcut: "B") {
                editingProxy.wrapSelection(prefix: "**", suffix: "**")
            }
            toolbarButton("Italic", icon: "italic", shortcut: "I") {
                editingProxy.wrapSelection(prefix: "*", suffix: "*")
            }
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Menu {
                Button("# Title") { editingProxy.setHeading(level: 1) }
                Button("## Heading") { editingProxy.setHeading(level: 2) }
                Button("### Subheading") { editingProxy.setHeading(level: 3) }
                Divider()
                Button("Clear Heading") { editingProxy.setHeading(level: 0) }
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
                editingProxy.toggleListItem()
            }
            toolbarButton("Quote", icon: "text.quote", shortcut: nil) {
                editingProxy.toggleBlockQuote()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Menu {
                Button("Code") { editingProxy.wrapSelection(prefix: "`", suffix: "`") }
                Button("Link") { editingProxy.insertLink() }
                Button("Wiki Link") { editingProxy.insertWikiLink() }
                Divider()
                Button("Strikethrough") { editingProxy.wrapSelection(prefix: "~~", suffix: "~~") }
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
            Text(wordCountLabel)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .padding(.trailing, 8)
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
                editingProxy.wrapSelection(prefix: "**", suffix: "**")
            }
            toolbarButton("Italic", icon: "italic", shortcut: "I") {
                editingProxy.wrapSelection(prefix: "*", suffix: "*")
            }

            Menu {
                Button("# Title") { editingProxy.setHeading(level: 1) }
                Button("## Heading") { editingProxy.setHeading(level: 2) }
                Button("### Subheading") { editingProxy.setHeading(level: 3) }
                Divider()
                Button("Clear Heading") { editingProxy.setHeading(level: 0) }
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
                editingProxy.toggleListItem()
            }
            toolbarButton("Quote", icon: "text.quote", shortcut: nil) {
                editingProxy.toggleBlockQuote()
            }

            Menu {
                Button("Code") { editingProxy.wrapSelection(prefix: "`", suffix: "`") }
                Button("Link") { editingProxy.insertLink() }
                Button("Wiki Link") { editingProxy.insertWikiLink() }
                Divider()
                Button("Strikethrough") { editingProxy.wrapSelection(prefix: "~~", suffix: "~~") }
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
            Text(wordCountLabel)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
    }

    private var editorContent: some View {
        MarkdownNSTextView(
            text: $text,
            minHeight: minHeight,
            fontSize: proseMode ? 18 : 15,
            textInset: proseMode ? NSSize(width: 40, height: 24) : NSSize(width: 8, height: 8),
            onWikiTrigger: handleWikiTrigger,
            editorProxy: editingProxy
        )
    }

    private func handleWikiTrigger(_ searchText: String?) {
        if let searchText {
            if wikiSearchText != searchText {
                wikiSearchText = searchText
            }
            if !showWikiPopover {
                showWikiPopover = true
            }
        } else {
            closeWikiPopover()
        }
    }

    private func closeWikiPopover() {
        if showWikiPopover {
            showWikiPopover = false
        }
        if !wikiSearchText.isEmpty {
            wikiSearchText = ""
        }
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
                    closeWikiPopover()
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
        editingProxy.replaceActiveWikiQuery(with: target.title)

        // Auto-create connection
        if let sourceItem {
            let viewModel = ItemViewModel(modelContext: modelContext)
            let alreadyConnected = sourceItem.outgoingConnections.contains { $0.targetItem?.id == target.id }
                || sourceItem.incomingConnections.contains { $0.sourceItem?.id == target.id }
            if !alreadyConnected {
                _ = viewModel.createConnection(source: sourceItem, target: target, type: .related)
            }
        }

        closeWikiPopover()
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
    var editorProxy: MarkdownEditingProxy? = nil

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
            paragraphStyle.lineSpacing = 2
            paragraphStyle.paragraphSpacing = 6
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
        context.coordinator.registerEditorProxy()

        scrollView.documentView = textView

        // Set initial text
        textView.string = text
        context.coordinator.applyHighlighting(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }
        context.coordinator.parent = self
        context.coordinator.textView = textView
        context.coordinator.registerEditorProxy()

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            context.coordinator.beginProgrammaticUpdate()
            textView.string = text
            context.coordinator.applyHighlighting(textView)
            textView.selectedRanges = selectedRanges
            context.coordinator.endProgrammaticUpdate()
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNSTextView
        weak var textView: HighlightingTextView?
        private var isUpdating = false
        private var lastWikiQuery: String??

        init(_ parent: MarkdownNSTextView) {
            self.parent = parent
        }

        func beginProgrammaticUpdate() {
            isUpdating = true
        }

        func endProgrammaticUpdate() {
            isUpdating = false
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
            applyHighlighting(textView)
            detectWikiLink(in: textView)
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            applyHighlighting(textView)
            detectWikiLink(in: textView)
            textView.needsDisplay = true
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

        func applyHighlighting(_ textView: NSTextView) {
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            let text = storage.string
            let selectedRange = textView.selectedRange()
            let maxLocation = (text as NSString).length
            let clampedLocation = min(max(0, selectedRange.location), maxLocation)
            let clampedLength = min(selectedRange.length, max(0, maxLocation - clampedLocation))
            let selectionState = MarkdownDocument.SelectionState(
                range: clampedLocation..<(clampedLocation + clampedLength)
            )
            let document = MarkdownDocument(text)

            let size = parent.fontSize
            let defaultFont = NSFont(name: "IBMPlexSans-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
            let monoFont = NSFont(name: "IBMPlexMono-Regular", size: size - 2) ?? NSFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
            let headingFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.55)) ?? NSFont.systemFont(ofSize: round(size * 1.55), weight: .medium)
            let headingSmallFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.22)) ?? NSFont.systemFont(ofSize: round(size * 1.22), weight: .medium)
            let headingMidFont = NSFont(name: "Newsreader-Medium", size: round(size * 1.08)) ?? NSFont.systemFont(ofSize: round(size * 1.08), weight: .medium)
            let quoteColor = NSColor.labelColor.withAlphaComponent(0.92)

            let primaryColor = NSColor.labelColor
            let secondaryColor = NSColor.secondaryLabelColor
            let tertiaryColor = NSColor.tertiaryLabelColor
            let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.15)

            // Build paragraph style for prose mode (generous line spacing)
            let proseParagraph: NSParagraphStyle? = {
                guard size >= 17 else { return nil }
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacing = 6
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
            if fullRange.length > 0 {
                storage.setAttributes(defaultAttrs, range: fullRange)
            }
            textView.typingAttributes = defaultAttrs
            storage.removeAttribute(.groveListPrefix, range: fullRange)
            storage.removeAttribute(.groveQuotePrefix, range: fullRange)

            guard fullRange.length > 0 else {
                storage.endEditing()
                restoreSelectionIfNeeded(
                    NSRange(location: clampedLocation, length: clampedLength),
                    in: textView
                )
                textView.needsDisplay = true
                return
            }

            let hiddenDelimiterAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.1)
            ]
            let hiddenListPrefixAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear
            ]
            let hiddenQuotePrefixAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear
            ]

            for block in document.blocks {
                switch block.kind {
                case .heading(let heading):
                    let revealMarkers = document.shouldRevealHeading(heading, for: selectionState)
                    let markerAttrs = revealMarkers
                        ? [.font: defaultFont, .foregroundColor: tertiaryColor]
                        : hiddenDelimiterAttrs
                    applyAttributes(markerAttrs, to: heading.markerRange, in: text, storage: storage)
                    applyAttributes(markerAttrs, to: heading.spacingRange, in: text, storage: storage)

                    let headingAttrs: [NSAttributedString.Key: Any]
                    switch heading.level {
                    case 1, 4, 5, 6:
                        headingAttrs = [.font: headingFont, .foregroundColor: primaryColor]
                    case 2:
                        headingAttrs = [.font: headingSmallFont, .foregroundColor: primaryColor]
                    default:
                        headingAttrs = [.font: headingMidFont, .foregroundColor: primaryColor]
                    }

                    applyAttributes(headingAttrs, to: heading.contentRange, in: text, storage: storage)

                    if let proseParagraph,
                       let lineRange = nsRange(for: block.range, in: text) {
                        storage.addAttribute(.paragraphStyle, value: proseParagraph, range: lineRange)
                    }

                case .blockquote(let blockquote):
                    for line in blockquote.lines {
                        let revealPrefix = document.shouldRevealPrefix(line.prefixRange, for: selectionState)
                        let prefixAttrs = revealPrefix
                            ? [.font: defaultFont, .foregroundColor: tertiaryColor]
                            : hiddenQuotePrefixAttrs
                        applyAttributes(prefixAttrs, to: line.prefixRange, in: text, storage: storage)
                        applyAttributes(
                            [.font: defaultFont, .foregroundColor: quoteColor],
                            to: line.contentRange,
                            in: text,
                            storage: storage
                        )
                        applyAttributes([.groveQuotePrefix: true], to: line.prefixRange, in: text, storage: storage)

                        if let lineRange = nsRange(for: line.lineRange, in: text) {
                            let existingStyle = (storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)
                                ?? NSParagraphStyle.default
                            let updatedStyle = quoteParagraphStyle(from: existingStyle, isProse: proseParagraph != nil)
                            storage.addAttribute(.paragraphStyle, value: updatedStyle, range: lineRange)
                        }
                    }

                case .bulletList(let list):
                    for item in list.items {
                        let revealPrefix = document.shouldRevealPrefix(item.prefixRange, for: selectionState)
                        let prefixAttrs = revealPrefix
                            ? [.font: defaultFont, .foregroundColor: tertiaryColor]
                            : hiddenListPrefixAttrs
                        applyAttributes(prefixAttrs, to: item.prefixRange, in: text, storage: storage)
                        applyAttributes(
                            [.font: defaultFont, .foregroundColor: primaryColor],
                            to: item.contentRange,
                            in: text,
                            storage: storage
                        )
                        applyAttributes([.groveListPrefix: true], to: item.prefixRange, in: text, storage: storage)

                        if let lineRange = nsRange(for: item.lineRange, in: text) {
                            let existingStyle = (storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)
                                ?? NSParagraphStyle.default
                            let updatedStyle = listParagraphStyle(from: existingStyle, isProse: proseParagraph != nil)
                            storage.addAttribute(.paragraphStyle, value: updatedStyle, range: lineRange)
                        }
                    }

                case .codeBlock(let codeBlock):
                    let openingAttrs = document.shouldRevealCodeFence(codeBlock.openingFenceRange, for: selectionState)
                        ? [.font: monoFont, .foregroundColor: tertiaryColor]
                        : hiddenDelimiterAttrs
                    applyAttributes(openingAttrs, to: codeBlock.openingFenceRange, in: text, storage: storage)

                    if let closingFenceRange = codeBlock.closingFenceRange {
                        let closingAttrs = document.shouldRevealCodeFence(closingFenceRange, for: selectionState)
                            ? [.font: monoFont, .foregroundColor: tertiaryColor]
                            : hiddenDelimiterAttrs
                        applyAttributes(closingAttrs, to: closingFenceRange, in: text, storage: storage)
                    }

                    if let contentRange = codeBlock.contentRange {
                        applyAttributes(
                            [
                                .font: monoFont,
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
                    defaultFont: defaultFont,
                    monoFont: monoFont,
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

                guard let contentRange = nsRange(for: span.contentRange, in: text) else { continue }

                switch span.kind {
                case .bold:
                    applyFontTraits(.boldFontMask, to: contentRange, in: storage)
                case .italic:
                    applyFontTraits(.italicFontMask, to: contentRange, in: storage)
                case .boldItalic:
                    applyFontTraits([.boldFontMask, .italicFontMask], to: contentRange, in: storage)
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                case .inlineCode:
                    storage.addAttributes(
                        [
                            .font: monoFont,
                            .backgroundColor: codeBackground,
                            .foregroundColor: primaryColor,
                        ],
                        range: contentRange
                    )
                case .wikiLink, .link:
                    storage.addAttributes(
                        [
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: secondaryColor,
                        ],
                        range: contentRange
                    )
                }
            }

            storage.endEditing()
            textView.typingAttributes = defaultAttrs
            restoreSelectionIfNeeded(
                NSRange(location: clampedLocation, length: clampedLength),
                in: textView
            )
            textView.needsDisplay = true
        }

        private func restoreSelectionIfNeeded(_ range: NSRange, in textView: NSTextView) {
            guard textView.selectedRange() != range else { return }
            textView.setSelectedRange(range)
        }

        private func delimiterAttributes(
            for kind: MarkdownDocument.InlineSpan.Kind,
            defaultFont: NSFont,
            monoFont: NSFont,
            tertiaryColor: NSColor,
            codeBackground: NSColor
        ) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .inlineCode:
                return [
                    .font: monoFont,
                    .foregroundColor: tertiaryColor,
                    .backgroundColor: codeBackground,
                ]
            default:
                return [
                    .font: defaultFont,
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
                return hiddenDelimiterAttrs.merging([.backgroundColor: NSColor.clear]) { _, new in new }
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

        private func applyFontTraits(
            _ traits: NSFontTraitMask,
            to nsRange: NSRange,
            in storage: NSTextStorage
        ) {
            storage.enumerateAttribute(.font, in: nsRange, options: []) { value, range, _ in
                let baseFont = (value as? NSFont) ?? (NSFont(name: "IBMPlexSans-Regular", size: self.parent.fontSize) ?? NSFont.systemFont(ofSize: self.parent.fontSize))
                let font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
                storage.addAttribute(.font, value: font, range: range)
            }
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
                let tokenAttributes = isEditingMatch ? delimiterAttributes : hiddenDelimiterAttributes

                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    if contentRange.location != NSNotFound {
                        let matchStart = match.range.location
                        let matchEnd = match.range.location + match.range.length
                        let contentStart = contentRange.location
                        let contentEnd = contentRange.location + contentRange.length

                        // Apply token style/hiding only to delimiter regions so content keeps normal glyph metrics.
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

                        // Group 1 (content) — apply content style on top.
                        storage.addAttributes(contentAttributes, range: contentRange)
                        return
                    }
                }

                // Fallback for patterns without a captured content group.
                storage.addAttributes(tokenAttributes, range: match.range)
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

        private func quoteParagraphStyle(from baseStyle: NSParagraphStyle, isProse: Bool) -> NSParagraphStyle {
            let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            style.textBlocks = []
            let indent: CGFloat = isProse ? 14 : 11
            let markerAdvance: CGFloat = isProse ? 11 : 9
            style.firstLineHeadIndent = indent
            style.headIndent = indent + markerAdvance
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            return style
        }

        private func listParagraphStyle(from baseStyle: NSParagraphStyle, isProse: Bool) -> NSParagraphStyle {
            let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            style.textLists = []
            style.firstLineHeadIndent = 0
            style.headIndent = isProse ? 14 : 12
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
            let lineWithLineBreak = nsText.substring(with: lineRange)
            let line = lineWithLineBreak.trimmingCharacters(in: .newlines)

            if let listLine = parseListLine(line) {
                let isEmptyItem = listLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmptyItem {
                    textView.insertText("\n", replacementRange: selected)
                } else {
                    textView.insertText("\n\(listLine.marker)\(listLine.spacer)", replacementRange: selected)
                }
                return true
            }
            if let quoteLine = parseQuoteLine(line) {
                let isEmptyQuote = quoteLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmptyQuote {
                    textView.insertText("\n", replacementRange: selected)
                } else {
                    textView.insertText("\n>\(quoteLine.spacer)", replacementRange: selected)
                }
                return true
            }
            return false
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

// MARK: - HighlightingTextView

/// Custom NSTextView subclass that handles formatting keyboard shortcuts.
class HighlightingTextView: NSTextView {
    static weak var focusedEditor: HighlightingTextView?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMarkdownQuoteRails(in: dirtyRect)
        drawMarkdownListBullets(in: dirtyRect)
    }

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

        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        if applyFormattingShortcut(for: key) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func toggleBoldface(_ sender: Any?) {
        wrapSelectionWith(prefix: "**", suffix: "**")
    }

    @objc func toggleItalics(_ sender: Any?) {
        wrapSelectionWith(prefix: "*", suffix: "*")
    }

    private func applyFormattingShortcut(for key: String) -> Bool {
        switch key {
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
            return false
        }
    }

    private func drawMarkdownListBullets(in dirtyRect: NSRect) {
        guard
            let storage = textStorage,
            let layoutManager = layoutManager,
            let textContainer = textContainer
        else { return }

        let selection = selectedRange()
        let textOrigin = textContainerOrigin
        let markerColor = NSColor.secondaryLabelColor.withAlphaComponent(0.9)
        let baseSize = font?.pointSize ?? 15
        let bulletSize: CGFloat = baseSize >= 17 ? 5.4 : 4.6
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(.groveListPrefix, in: fullRange, options: []) { value, range, _ in
            guard let isListPrefix = value as? Bool, isListPrefix, range.length > 0 else { return }

            if selection.length > 0, NSIntersectionRange(selection, range).length > 0 { return }
            if selection.length == 0 {
                let cursor = selection.location
                if cursor >= range.location && cursor < range.location + range.length { return }
            }

            let markerCharRange = NSRange(location: range.location, length: 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: markerCharRange, actualCharacterRange: nil)
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { return }

            var glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            glyphRect.origin.x += textOrigin.x
            glyphRect.origin.y += textOrigin.y
            guard glyphRect.intersects(dirtyRect) else { return }

            let bulletRect = NSRect(
                x: glyphRect.midX - bulletSize / 2,
                y: glyphRect.midY - bulletSize / 2 + 0.4,
                width: bulletSize,
                height: bulletSize
            )

            markerColor.setFill()
            NSBezierPath(ovalIn: bulletRect).fill()
        }
    }

    private func drawMarkdownQuoteRails(in dirtyRect: NSRect) {
        guard
            let storage = textStorage,
            let layoutManager = layoutManager,
            let textContainer = textContainer
        else { return }

        let nsText = storage.string as NSString
        let selection = selectedRange()
        let textOrigin = textContainerOrigin
        let railColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.72)
        let baseSize = font?.pointSize ?? 15
        let railWidth: CGFloat = baseSize >= 17 ? 1.0 : 0.85
        let fullRange = NSRange(location: 0, length: storage.length)

        struct QuoteLinePrefix {
            let prefixRange: NSRange
            let lineRange: NSRange
        }

        var prefixes: [QuoteLinePrefix] = []
        storage.enumerateAttribute(.groveQuotePrefix, in: fullRange, options: []) { value, range, _ in
            guard let isQuotePrefix = value as? Bool, isQuotePrefix, range.length > 0 else { return }

            if selection.length > 0, NSIntersectionRange(selection, range).length > 0 { return }
            if selection.length == 0, selection.location >= range.location, selection.location < range.location + range.length {
                return
            }

            let fullLineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let lineRange = trimmedLineRange(fullLineRange, in: nsText, fallback: range)
            prefixes.append(QuoteLinePrefix(prefixRange: range, lineRange: lineRange))
        }

        guard !prefixes.isEmpty else { return }
        prefixes.sort { $0.lineRange.location < $1.lineRange.location }

        struct QuoteBlock {
            var firstPrefixLocation: Int
            var blockLineRange: NSRange
        }

        var blocks: [QuoteBlock] = []
        for entry in prefixes {
            if var last = blocks.last {
                let lastEnd = last.blockLineRange.location + last.blockLineRange.length
                let currentEnd = entry.lineRange.location + entry.lineRange.length
                if entry.lineRange.location <= lastEnd + 2 {
                    last.blockLineRange = NSRange(
                        location: last.blockLineRange.location,
                        length: max(lastEnd, currentEnd) - last.blockLineRange.location
                    )
                    blocks[blocks.count - 1] = last
                    continue
                }
            }

            blocks.append(
                QuoteBlock(
                    firstPrefixLocation: entry.prefixRange.location,
                    blockLineRange: entry.lineRange
                )
            )
        }

        for block in blocks {
            let markerCharRange = NSRange(location: block.firstPrefixLocation, length: 1)
            let markerGlyphRange = layoutManager.glyphRange(forCharacterRange: markerCharRange, actualCharacterRange: nil)
            let blockGlyphRange = layoutManager.glyphRange(forCharacterRange: block.blockLineRange, actualCharacterRange: nil)
            guard markerGlyphRange.length > 0, blockGlyphRange.length > 0 else { continue }

            var markerRect = layoutManager.boundingRect(forGlyphRange: markerGlyphRange, in: textContainer)
            var blockRect = layoutManager.boundingRect(forGlyphRange: blockGlyphRange, in: textContainer)
            markerRect.origin.x += textOrigin.x
            markerRect.origin.y += textOrigin.y
            blockRect.origin.x += textOrigin.x
            blockRect.origin.y += textOrigin.y
            guard blockRect.intersects(dirtyRect) else { continue }

            let railRect = NSRect(
                x: markerRect.minX + 1.4,
                y: blockRect.minY + 1,
                width: railWidth,
                height: max(10, blockRect.height - 2)
            )

            railColor.setFill()
            NSBezierPath(roundedRect: railRect, xRadius: railWidth / 2, yRadius: railWidth / 2).fill()
        }
    }

    private func trimmedLineRange(_ lineRange: NSRange, in text: NSString, fallback: NSRange) -> NSRange {
        guard lineRange.length > 0 else { return fallback }

        let lineStart = lineRange.location
        var lineEnd = lineRange.location + lineRange.length
        while lineEnd > lineStart {
            let scalar = text.character(at: lineEnd - 1)
            if scalar == 10 || scalar == 13 {
                lineEnd -= 1
            } else {
                break
            }
        }

        let trimmedLength = lineEnd - lineStart
        if trimmedLength > 0 {
            return NSRange(location: lineStart, length: trimmedLength)
        }
        return fallback
    }

    func wrapSelectionWith(prefix: String, suffix: String) {
        let selectedRange = self.selectedRange()
        guard let textStorage = self.textStorage else { return }
        let prefixLength = utf16Length(of: prefix)
        let suffixLength = utf16Length(of: suffix)

        if selectedRange.length == 0 {
            let insertion = prefix + suffix
            if shouldChangeText(in: selectedRange, replacementString: insertion) {
                textStorage.replaceCharacters(in: selectedRange, with: insertion)
                didChangeText()
                setSelectedRange(NSRange(location: selectedRange.location + prefixLength, length: 0))
            }
            return
        }

        let nsText = textStorage.string as NSString
        let selectedText = nsText.substring(with: selectedRange)
        let segments = splitOuterWhitespace(selectedText)

        if !segments.core.isEmpty,
           segments.core.hasPrefix(prefix),
           segments.core.hasSuffix(suffix),
           utf16Length(of: segments.core) >= prefixLength + suffixLength {
            let coreText = segments.core as NSString
            let innerRange = NSRange(
                location: prefixLength,
                length: coreText.length - prefixLength - suffixLength
            )
            let inner = coreText.substring(with: innerRange)
            let replacement = segments.leading + inner + segments.trailing

            if shouldChangeText(in: selectedRange, replacementString: replacement) {
                textStorage.replaceCharacters(in: selectedRange, with: replacement)
                didChangeText()
                let newStart = selectedRange.location + utf16Length(of: segments.leading)
                setSelectedRange(NSRange(location: newStart, length: utf16Length(of: inner)))
            }
            return
        }

        let replacement: String
        let selectionStart: Int
        let selectionLength: Int

        if segments.core.isEmpty {
            replacement = prefix + selectedText + suffix
            selectionStart = selectedRange.location + prefixLength
            selectionLength = selectedRange.length
        } else {
            replacement = segments.leading + prefix + segments.core + suffix + segments.trailing
            selectionStart = selectedRange.location + utf16Length(of: segments.leading) + prefixLength
            selectionLength = utf16Length(of: segments.core)
        }

        if shouldChangeText(in: selectedRange, replacementString: replacement) {
            textStorage.replaceCharacters(in: selectedRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: selectionStart, length: selectionLength))
        }
    }

    private func splitOuterWhitespace(_ text: String) -> (leading: String, core: String, trailing: String) {
        var start = text.startIndex
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }

        var end = text.endIndex
        while end > start {
            let before = text.index(before: end)
            if text[before].isWhitespace {
                end = before
            } else {
                break
            }
        }

        return (
            leading: String(text[..<start]),
            core: String(text[start..<end]),
            trailing: String(text[end...])
        )
    }

    private func utf16Length(of text: String) -> Int {
        (text as NSString).length
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

    func toggleLinePrefix(_ prefix: String) {
        let selectedRange = selectedRange()
        let nsText = string as NSString
        let blockRange = selectedLineBlockRange(in: nsText, selection: selectedRange)
        let lines = nsText.substring(with: blockRange).components(separatedBy: "\n")
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let shouldRemovePrefix = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { $0.hasPrefix(prefix) }

        let replaced = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if shouldRemovePrefix {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            }
            return prefix + line
        }.joined(separator: "\n")

        guard let textStorage else { return }
        if shouldChangeText(in: blockRange, replacementString: replaced) {
            textStorage.replaceCharacters(in: blockRange, with: replaced)
            didChangeText()

            if selectedRange.length == 0 {
                let newCursor = min(
                    blockRange.location + (shouldRemovePrefix ? 0 : utf16Length(of: prefix)),
                    blockRange.location + (replaced as NSString).length
                )
                setSelectedRange(NSRange(location: newCursor, length: 0))
            } else {
                setSelectedRange(NSRange(location: blockRange.location, length: (replaced as NSString).length))
            }
        }
    }

    func setHeadingLevel(_ level: Int) {
        let clampedLevel = min(max(level, 0), 6)
        let prefix = clampedLevel > 0 ? String(repeating: "#", count: clampedLevel) + " " : ""

        let selectedRange = selectedRange()
        let nsText = string as NSString
        let blockRange = selectedLineBlockRange(in: nsText, selection: selectedRange)
        let lines = nsText.substring(with: blockRange).components(separatedBy: "\n")
        let replaced = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            return prefix + lineRemovingHeadingPrefix(line)
        }.joined(separator: "\n")

        guard let textStorage else { return }
        if shouldChangeText(in: blockRange, replacementString: replaced) {
            textStorage.replaceCharacters(in: blockRange, with: replaced)
            didChangeText()

            if selectedRange.length == 0 {
                let newCursor = min(
                    blockRange.location + utf16Length(of: prefix),
                    blockRange.location + (replaced as NSString).length
                )
                setSelectedRange(NSRange(location: newCursor, length: 0))
            } else {
                setSelectedRange(NSRange(location: blockRange.location, length: (replaced as NSString).length))
            }
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

    private func selectedLineBlockRange(in text: NSString, selection: NSRange) -> NSRange {
        let startLineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let endAnchor: Int
        if selection.length > 0 {
            endAnchor = max(selection.location, selection.location + selection.length - 1)
        } else {
            endAnchor = selection.location
        }
        let endLineRange = text.lineRange(for: NSRange(location: min(endAnchor, max(0, text.length - 1)), length: 0))
        let location = startLineRange.location
        let upperBound = max(NSMaxRange(startLineRange), NSMaxRange(endLineRange))
        return NSRange(location: location, length: upperBound - location)
    }

    private func lineRemovingHeadingPrefix(_ line: String) -> String {
        var index = line.startIndex
        var hashCount = 0
        while index < line.endIndex, line[index] == "#", hashCount < 6 {
            hashCount += 1
            index = line.index(after: index)
        }

        guard hashCount > 0, index < line.endIndex, line[index] == " " else {
            return line
        }

        let contentStart = line.index(after: index)
        return String(line[contentStart...])
    }
}
#else
import SwiftUI
import SwiftData
import UIKit

/// iOS rich markdown editor using UITextView for live syntax highlighting,
/// formatting toolbar, keyboard shortcuts, wiki-link autocomplete, and
/// smart list/quote continuation. Mirrors the macOS NSTextView implementation.
struct RichMarkdownEditor: View {
    @Binding var text: String
    var sourceItem: Item?
    var minHeight: CGFloat = 80
    var proseMode: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]

    @State private var editingProxy = MarkdownEditingProxy()
    @State private var showWikiPopover = false
    @State private var wikiSearchText = ""

    private var showsInlineToolbar: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var wikiSearchResults: [Item] {
        allItems.filter { candidate in
            if let sourceItem, candidate.id == sourceItem.id { return false }
            if wikiSearchText.isEmpty { return true }
            return candidate.title.localizedStandardContains(wikiSearchText)
        }.prefix(10).map { $0 }
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                if showsInlineToolbar {
                    formattingToolbar
                        .padding(.horizontal, proseMode ? 20 : 8)
                        .padding(.bottom, 6)
                }

                MarkdownUITextView(
                    text: $text,
                    minHeight: minHeight,
                    fontSize: proseMode ? 18 : 16,
                    textInset: proseMode
                        ? UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
                        : UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8),
                    onWikiTrigger: { searchText in
                        if let searchText {
                            wikiSearchText = searchText
                            showWikiPopover = true
                        } else {
                            showWikiPopover = false
                            wikiSearchText = ""
                        }
                    },
                    editorProxy: editingProxy
                )
                .frame(minHeight: minHeight)

                if showWikiPopover {
                    wikiLinkDropdown
                        .padding(.horizontal, proseMode ? 20 : 8)
                }
            }
        }
        .onDisappear {
            editingProxy.clear()
        }
    }

    // MARK: - iPad Inline Formatting Toolbar

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolbarButton("Bold", icon: "bold") {
                    editingProxy.wrapSelection(prefix: "**", suffix: "**")
                }
                toolbarButton("Italic", icon: "italic") {
                    editingProxy.wrapSelection(prefix: "*", suffix: "*")
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                Menu {
                    Button("# Title") { editingProxy.setHeading(level: 1) }
                    Button("## Heading") { editingProxy.setHeading(level: 2) }
                    Button("### Subheading") { editingProxy.setHeading(level: 3) }
                    Divider()
                    Button("Clear Heading") { editingProxy.setHeading(level: 0) }
                } label: {
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)

                toolbarButton("List", icon: "list.bullet") {
                    editingProxy.toggleListItem()
                }
                toolbarButton("Quote", icon: "text.quote") {
                    editingProxy.toggleBlockQuote()
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                toolbarButton("Code", icon: "chevron.left.forwardslash.chevron.right") {
                    editingProxy.wrapSelection(prefix: "`", suffix: "`")
                }
                toolbarButton("Link", icon: "link") {
                    editingProxy.insertLink()
                }
                toolbarButton("Wiki Link", icon: "link.badge.plus") {
                    editingProxy.insertWikiLink()
                }
                toolbarButton("Strikethrough", icon: "strikethrough") {
                    editingProxy.wrapSelection(prefix: "~~", suffix: "~~")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.borderInput, lineWidth: 1)
        )
    }

    private func toolbarButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textSecondary)
        .help(label)
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
        let originalText = text
        editingProxy.replaceActiveWikiQuery(with: target.title)

        if text == originalText {
            replaceTrailingWikiQueryFallback(with: target.title)
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

    private func replaceTrailingWikiQueryFallback(with title: String) {
        guard let openRange = text.range(of: "[[", options: .backwards) else { return }

        let suffix = text[openRange.upperBound...]
        guard !suffix.contains("]]"), !suffix.contains("\n") else { return }

        text.replaceSubrange(openRange.lowerBound..<text.endIndex, with: "[[\(title)]]")
    }
}
#endif
