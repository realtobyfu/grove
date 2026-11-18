#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

private extension NSAttributedString.Key {
    static let groveListPrefix = NSAttributedString.Key("groveListPrefix")
    static let groveQuotePrefix = NSAttributedString.Key("groveQuotePrefix")
    /// String — `wiki:<title>` or a URL. ⌘-click opens it.
    static let groveLink = NSAttributedString.Key("groveLink")
    /// Bool (is it checked) on the `[ ]` of a task item. A click toggles it.
    static let groveTaskMarker = NSAttributedString.Key("groveTaskMarker")
    /// Marks a hidden `---` line; the text view draws a hairline across it.
    static let groveDivider = NSAttributedString.Key("groveDivider")
}

// MARK: - RichMarkdownEditor

/// A writing surface that stores markdown as the source of truth and renders
/// it live (bold, italic, code, headings, lists, tasks, dividers, wiki-links)
/// in an NSTextView.
///
/// Formatting sits in one quiet strip of SF Symbol buttons: under the page in
/// prose mode, over the box in the compact editor. The keyboard (⌘B/I/E/K)
/// and a `/` menu at the start of a line reach the same actions, and `[[`
/// opens a link picker at the caret; both popups are driven from the keyboard
/// without leaving the text.
struct RichMarkdownEditor: View {
    @Binding var text: String
    var sourceItem: Item?
    var minHeight: CGFloat = 80
    var proseMode: Bool = false
    /// A host that needs to reach the caret (insert a reference, move focus
    /// into the body) passes its own proxy; otherwise the editor keeps one.
    var proxy: MarkdownEditingProxy? = nil
    /// Shown in the toolbar beside the word count ("Saved", "Edited").
    var status: String? = nil
    /// Called when a `[[wiki link]]` is ⌘-clicked and resolves to an item.
    var onNavigateToItem: ((Item) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var allItems: [Item]

    @State private var ownedProxy = MarkdownEditingProxy()
    @State private var assist: EditorAssistTrigger?
    /// Where the token being completed starts, in the editor's own space.
    @State private var assistAnchor: CGRect = .zero
    @State private var assistHighlight = 0
    /// Escape closes the popup for the token being typed; it stays closed
    /// until that token ends.
    @State private var assistDismissed = false
    @State private var isFocused = false

    private var editingProxy: MarkdownEditingProxy { proxy ?? ownedProxy }

    private var wordCountLabel: String {
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        return "\(wordCount) \(wordCount == 1 ? "word" : "words")"
    }

    var body: some View {
        Group {
            if proseMode {
                VStack(spacing: 0) {
                    // Fills the panel so the caret starts at the top of the
                    // page instead of being centred in dead space.
                    textSurface
                        .frame(minHeight: minHeight, maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .topLeading) { floatingLayer }
                    EditorToolbar(
                        proxy: editingProxy,
                        layout: .prose,
                        wordCount: wordCountLabel,
                        status: status
                    )
                    .padding(.horizontal, LayoutDimensions.writingGutter)
                    .padding(.vertical, Spacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    EditorToolbar(
                        proxy: editingProxy,
                        layout: .boxed,
                        wordCount: wordCountLabel,
                        status: status
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control)
                            .stroke(Color.borderInput, lineWidth: 1)
                    )

                    textSurface
                        .frame(minHeight: minHeight)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control)
                                .stroke(Color.borderInput, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) { floatingLayer }
                }
            }
        }
        .onDisappear {
            editingProxy.clear()
        }
    }

    private var textSurface: some View {
        MarkdownNSTextView(
            text: $text,
            minHeight: minHeight,
            fontSize: proseMode ? MarkdownTypeSpec.proseBodySize : 15,
            textInset: proseMode
                ? NSSize(width: LayoutDimensions.writingGutter, height: Spacing.sm)
                : NSSize(width: Spacing.sm, height: Spacing.sm),
            onAssistTrigger: { applyAssist($0, anchor: $1) },
            onAssistKey: { handleAssistKey($0) },
            onFocusChange: { isFocused = $0 },
            onOpenLink: { openLink($0) },
            editorProxy: editingProxy
        )
    }

    // MARK: - Floating Layer (assist popup)

    private enum FloatingMetrics {
        static let popupWidth: CGFloat = 300
        static let rowHeight: CGFloat = 26
        /// Enough for every block command: the popup does not scroll, so a
        /// row past this count would be laid out below its frame and cut off.
        static let maxRows = 10
        static let gap: CGFloat = 4
        static let edge: CGFloat = 8
    }

    private var isAssistVisible: Bool {
        guard isFocused, let assist, !assistDismissed else { return false }
        // A slash that matches nothing is just a slash.
        return !(assist.isSlash && assistRows.isEmpty)
    }

    @ViewBuilder
    private var floatingLayer: some View {
        GeometryReader { geo in
            if isAssistVisible {
                let rows = assistRows
                let shown = max(1, min(rows.count, FloatingMetrics.maxRows))
                let height = CGFloat(shown) * FloatingMetrics.rowHeight + Spacing.xs * 2
                EditorAssistPopup(
                    rows: rows,
                    highlighted: assistHighlight,
                    emptyLabel: "No matching items",
                    rowHeight: FloatingMetrics.rowHeight,
                    onPick: { commitAssist($0) }
                )
                .frame(width: FloatingMetrics.popupWidth, height: height)
                .offset(popupOffset(anchor: assistAnchor, height: height, in: geo.size))
            }
        }
    }

    /// Under the caret; above it when there is no room below.
    private func popupOffset(anchor: CGRect, height: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max(FloatingMetrics.edge, size.width - FloatingMetrics.popupWidth - FloatingMetrics.edge)
        let x = min(max(anchor.minX, FloatingMetrics.edge), maxX)
        var y = anchor.maxY + FloatingMetrics.gap
        let above = anchor.minY - FloatingMetrics.gap - height
        if y + height > size.height, above >= 0 {
            y = above
        }
        return CGSize(width: x, height: y)
    }

    // MARK: - Assist

    private var assistRows: [EditorAssistRow] {
        switch assist {
        case .wikiLink(let query):
            return wikiCandidates(for: query).map { item in
                EditorAssistRow(
                    id: item.id.uuidString,
                    title: item.title,
                    hint: item.type.displayName,
                    action: .item(item)
                )
            }
        case .slash(let query):
            return EditorBlockCommand.matching(query).map { command in
                EditorAssistRow(id: command.id, title: command.title, hint: command.hint, action: .command(command))
            }
        case nil:
            return []
        }
    }

    /// Titles that start with the query first, then titles that contain it;
    /// most recently touched first within each. With nothing typed yet, the
    /// most recent items — usually what a note is about to cite.
    private func wikiCandidates(for query: String) -> [Item] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let pool = allItems.filter { candidate in
            if let sourceItem, candidate.id == sourceItem.id { return false }
            if candidate.title.isEmpty { return false }
            return needle.isEmpty || candidate.title.localizedStandardContains(needle)
        }
        let ranked = pool.sorted { lhs, rhs in
            if !needle.isEmpty {
                let lhsPrefix = lhs.title.lowercased().hasPrefix(needle.lowercased())
                let rhsPrefix = rhs.title.lowercased().hasPrefix(needle.lowercased())
                if lhsPrefix != rhsPrefix { return lhsPrefix }
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        return Array(ranked.prefix(FloatingMetrics.maxRows))
    }

    /// The text view reports what the caret is typing. Deferred a turn by the
    /// coordinator, so this never runs inside a view update.
    private func applyAssist(_ trigger: EditorAssistTrigger?, anchor: CGRect) {
        if trigger == nil {
            assistDismissed = false
        } else {
            assistAnchor = anchor
        }
        if assist != trigger {
            assist = trigger
            assistHighlight = 0
        }
    }

    /// Arrow keys, Return/Tab and Escape while a popup is open. Returning
    /// false hands the key back to the text view.
    private func handleAssistKey(_ key: EditorAssistKey) -> Bool {
        guard isAssistVisible else { return false }
        let rows = assistRows

        switch key {
        // With nothing to pick, the arrows belong to the text: a stray `[[`
        // must not trap the caret on its line.
        case .down:
            guard !rows.isEmpty else { return false }
            assistHighlight = (assistHighlight + 1) % rows.count
            return true
        case .up:
            guard !rows.isEmpty else { return false }
            assistHighlight = (assistHighlight - 1 + rows.count) % rows.count
            return true
        case .commit:
            guard rows.indices.contains(assistHighlight) else { return false }
            commitAssist(rows[assistHighlight])
            return true
        case .cancel:
            assistDismissed = true
            return true
        }
    }

    private func commitAssist(_ row: EditorAssistRow) {
        switch row.action {
        case .item(let item):
            insertWikiLink(for: item)
        case .command(let command):
            editingProxy.replaceActiveSlashQuery(with: command.insertion, cursorOffset: command.cursorOffset)
        }
        assist = nil
        assistDismissed = false
        assistHighlight = 0
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
    }

    /// ⌘-click on a link in the text.
    private func openLink(_ target: String) {
        if target.hasPrefix("wiki:") {
            let title = String(target.dropFirst(5))
            if let item = ItemResolver.resolveExactTitle(title, in: allItems, excluding: sourceItem?.id) {
                onNavigateToItem?(item)
            }
        } else if let url = URL(string: target), url.scheme != nil {
            openURL(url)
        }
    }
}

// MARK: - Assist Popup

struct EditorAssistRow: Identifiable {
    enum Action {
        case item(Item)
        case command(EditorBlockCommand)
    }

    let id: String
    let title: String
    /// Mono, trailing: the item's kind, or the markdown a command stands for.
    let hint: String
    let action: Action
}

/// The list that opens at the caret for `[[` and `/`. Flat: a hairline box on
/// the card colour, the highlighted row marked the way a selected row is
/// everywhere else in the app.
private struct EditorAssistPopup: View {
    let rows: [EditorAssistRow]
    let highlighted: Int
    let emptyLabel: String
    let rowHeight: CGFloat
    let onPick: (EditorAssistRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text(emptyLabel)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: rowHeight, alignment: .leading)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        onPick(row)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Text(row.title)
                                .font(.groveBodySecondary)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Spacing.sm)
                            Text(row.hint)
                                .font(.groveFolio)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, Spacing.md)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                        .selectedItemStyle(index == highlighted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == highlighted ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }
}

// MARK: - Toolbar

/// The editor's formatting strip: SF Symbol buttons in secondary ink, a
/// heading menu and a "more" menu, with the word count and saved state at the
/// trailing end. One implementation for both editors — spaced out under the
/// page in prose mode, packed into groups over the compact (boxed) editor.
private struct EditorToolbar: View {
    enum Layout { case prose, boxed }

    let proxy: MarkdownEditingProxy
    let layout: Layout
    let wordCount: String
    var status: String?

    private var spacing: CGFloat {
        layout == .prose ? Spacing.md : 2
    }

    var body: some View {
        HStack(spacing: spacing) {
            EditorToolbarButton(symbol: "bold", name: "Bold", shortcut: "B") {
                proxy.wrapSelection(prefix: "**", suffix: "**")
            }
            EditorToolbarButton(symbol: "italic", name: "Italic", shortcut: "I") {
                proxy.wrapSelection(prefix: "*", suffix: "*")
            }

            groupBreak

            EditorToolbarMenu(symbol: "number", name: "Heading") {
                Button("Title") { proxy.setHeading(level: 1) }
                Button("Heading") { proxy.setHeading(level: 2) }
                Button("Subheading") { proxy.setHeading(level: 3) }
                Divider()
                Button("Body Text") { proxy.setHeading(level: 0) }
            }
            EditorToolbarButton(symbol: "list.bullet", name: "List") {
                proxy.toggleListItem()
            }
            EditorToolbarButton(symbol: "text.quote", name: "Quote") {
                proxy.toggleBlockQuote()
            }

            groupBreak

            EditorToolbarMenu(symbol: "ellipsis", name: "More") {
                Button("Task") { proxy.insertPrefix("- [ ] ") }
                Button("Code") { proxy.wrapSelection(prefix: "`", suffix: "`") }
                Button("Strikethrough") { proxy.wrapSelection(prefix: "~~", suffix: "~~") }
                Divider()
                Button("Link") { proxy.insertLink() }
                Button("Link to an Item") { proxy.insertWikiLink() }
            }

            Spacer(minLength: Spacing.sm)

            HStack(spacing: Spacing.xsm) {
                Text(wordCount)
                if let status {
                    Text("\u{00B7}")
                        .accessibilityHidden(true)
                    Text(status)
                        .accessibilityLabel("Note \(status)")
                }
            }
            .font(.groveMeta)
            .foregroundStyle(Color.textTertiary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, layout == .boxed ? Spacing.xs : 0)
        }
    }

    /// Prose mode separates groups with space alone; the packed strip needs
    /// a hairline to show where one group ends.
    @ViewBuilder
    private var groupBreak: some View {
        if layout == .boxed {
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(width: 1, height: 14)
                .padding(.horizontal, Spacing.xs)
        }
    }
}

/// The square every toolbar control sits on: secondary ink at rest; primary
/// ink on a soft wash under the pointer, darker while pressed.
private struct EditorToolbarGlyph: View {
    let symbol: String
    let isHovering: Bool
    var isPressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovering || isPressed ? Color.textPrimary : Color.textSecondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(isPressed ? Color.bgCardHover : (isHovering ? Color.bgCardHover.opacity(0.6) : Color.clear))
            )
            .contentShape(Rectangle())
    }
}

private struct EditorToolbarButton: View {
    let symbol: String
    let name: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            EditorToolbarGlyph(symbol: symbol, isHovering: isHovering)
        }
        .buttonStyle(EditorToolbarPressStyle(symbol: symbol, isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help(shortcut.map { "\(name) (\u{2318}\($0))" } ?? name)
        .accessibilityLabel(name)
    }
}

/// Swaps in the pressed look; the label above is only used for its layout.
private struct EditorToolbarPressStyle: ButtonStyle {
    let symbol: String
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        EditorToolbarGlyph(symbol: symbol, isHovering: isHovering, isPressed: configuration.isPressed)
    }
}

private struct EditorToolbarMenu<Content: View>: View {
    let symbol: String
    let name: String
    @ViewBuilder var content: Content

    @State private var isHovering = false

    var body: some View {
        Menu {
            content
        } label: {
            EditorToolbarGlyph(symbol: symbol, isHovering: isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help(name)
        .accessibilityLabel(name)
    }
}

// MARK: - NSTextView Representable

/// NSViewRepresentable wrapping an NSTextView with live markdown rendering.
struct MarkdownNSTextView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var fontSize: CGFloat = 15
    var textInset: NSSize = NSSize(width: 8, height: 8)
    /// The `[[` / `/` token at the caret (nil when there is none) and where it
    /// starts, in this view's top-left coordinate space.
    var onAssistTrigger: ((EditorAssistTrigger?, CGRect) -> Void)?
    /// The first line of a non-empty selection, in the same space; nil when
    /// the selection is a caret.
    var onSelectionAnchor: ((CGRect?) -> Void)?
    /// Offered navigation keys first while a popup is open. Return true to
    /// consume the key.
    var onAssistKey: ((EditorAssistKey) -> Bool)?
    var onFocusChange: ((Bool) -> Void)?
    var onOpenLink: ((String) -> Void)?
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
        textView.insertionPointColor = EditorInk.primary

        // Set default font
        let defaultFont = NSFont(name: MarkdownTypeSpec.FontName.body, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

        // Build typing attributes — add generous line spacing for prose mode
        var typingAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: EditorInk.primary
        ]
        if fontSize >= 17 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = MarkdownTypeSpec.proseLineSpacing
            paragraphStyle.paragraphSpacing = MarkdownTypeSpec.proseParagraphSpacing
            typingAttrs[.paragraphStyle] = paragraphStyle
        }

        textView.font = defaultFont
        textView.typingAttributes = typingAttrs
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .limited
            textView.allowedWritingToolsResultOptions = [.plainText, .list]
        }

        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.onFocusChange = { [weak coordinator] focused in
            coordinator?.focusDidChange(focused)
        }
        textView.onOpenLink = { [weak coordinator] target in
            coordinator?.parent.onOpenLink?(target)
        }
        coordinator.textView = textView
        coordinator.registerEditorProxy()

        scrollView.documentView = textView

        // The popup is placed in this view's space, so it has to follow the
        // text when it scrolls.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Set initial text
        textView.string = text
        coordinator.applyHighlighting(textView)

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
            // Put the caret back first, so the markers are styled for where
            // it really is.
            let length = (textView.string as NSString).length
            textView.selectedRanges = selectedRanges.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
            // Replacing the string dropped every attribute, so nothing that
            // was styled before can be assumed still styled.
            context.coordinator.invalidateStyling()
            context.coordinator.applyHighlighting(textView)
            context.coordinator.endProgrammaticUpdate()
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNSTextView
        weak var textView: HighlightingTextView?
        private var isUpdating = false
        private var lastTrigger: EditorAssistTrigger?
        private var lastSelectionAnchor: CGRect?
        /// The parse of the text as last styled. A caret move leaves the text
        /// alone, so it reuses this instead of parsing again.
        private var styleCache: StyleCache?
        /// The selection the storage's current attributes were styled for.
        private var lastStyledSelection: NSRange?
        private var fonts: EditorFonts?

        init(_ parent: MarkdownNSTextView) {
            self.parent = parent
        }

        func beginProgrammaticUpdate() {
            isUpdating = true
        }

        func endProgrammaticUpdate() {
            isUpdating = false
        }

        func invalidateStyling() {
            lastStyledSelection = nil
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
                    },
                    replaceActiveSlashQuery: { [weak textView] insertion, cursorOffset in
                        textView?.replaceActiveSlashQuery(with: insertion, cursorOffset: cursorOffset)
                    },
                    focus: { [weak textView] in
                        guard let textView else { return }
                        textView.window?.makeFirstResponder(textView)
                    }
                )
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            applyHighlighting(textView)
            publishCaretState(for: textView)
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            applyHighlighting(textView)
            publishCaretState(for: textView)
            // Bullets and quote rails are drawn, not typeset, and step aside
            // for the caret.
            textView.needsDisplay = true
            isUpdating = false
        }

        @objc func clipViewBoundsDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            publishCaretState(for: textView, force: true)
        }

        func focusDidChange(_ focused: Bool) {
            Task { @MainActor [weak self] in
                self?.parent.onFocusChange?(focused)
            }
        }

        // MARK: - Caret State (assist trigger, selection anchor)

        /// Tells the SwiftUI side what the caret is typing and where, so the
        /// popup can sit beside the text it acts on.
        /// Delivered a turn later: a delegate callback can arrive while
        /// SwiftUI is mid-update.
        private func publishCaretState(for textView: NSTextView, force: Bool = false) {
            let nsText = textView.string as NSString
            let selection = textView.selectedRange()
            let caret = min(max(0, selection.location), nsText.length)

            var trigger: EditorAssistTrigger?
            var anchor = CGRect.zero
            if selection.length == 0 {
                let lineStart = nsText.lineRange(for: NSRange(location: caret, length: 0)).location
                let linePrefix = nsText.substring(with: NSRange(location: lineStart, length: caret - lineStart))
                if let detected = EditorAssistTrigger.detect(linePrefix: linePrefix) {
                    trigger = detected.trigger
                    let tokenStart = max(lineStart, caret - detected.tokenLength)
                    anchor = editorRect(for: NSRange(location: tokenStart, length: 0), in: textView) ?? .zero
                }
            }
            if trigger != lastTrigger || (force && trigger != nil) {
                lastTrigger = trigger
                let reportedTrigger = trigger
                let reportedAnchor = anchor
                Task { @MainActor [weak self] in
                    self?.parent.onAssistTrigger?(reportedTrigger, reportedAnchor)
                }
            }

            let selectionAnchor = selection.length > 0 ? editorRect(for: selection, in: textView) : nil
            if selectionAnchor != lastSelectionAnchor {
                lastSelectionAnchor = selectionAnchor
                Task { @MainActor [weak self] in
                    self?.parent.onSelectionAnchor?(selectionAnchor)
                }
            }
        }

        /// The first rect of a character range in the scroll view's top-left
        /// coordinate space — the space the SwiftUI overlay is laid out in.
        private func editorRect(for range: NSRange, in textView: NSTextView) -> CGRect? {
            guard let window = textView.window, let scrollView = textView.enclosingScrollView else { return nil }
            let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard screenRect != .zero else { return nil }
            var rect = scrollView.convert(window.convertFromScreen(screenRect), from: nil)
            if !scrollView.isFlipped {
                rect.origin.y = scrollView.bounds.height - rect.maxY
            }
            return rect
        }

        // MARK: - Live Styling

        /// Brings the storage's attributes in line with the markdown and the
        /// caret.
        ///
        /// The styled text is built off to the side, then compared with the
        /// storage one paragraph at a time; only paragraphs that differ are
        /// written. Setting attributes on a range re-lays it out, so resetting
        /// the whole note on every keystroke and every caret move — what this
        /// used to do — re-laid out the whole note each time. A keystroke now
        /// touches the paragraph it lands in, and a caret move touches the
        /// lines whose markers it reveals or hides.
        func applyHighlighting(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            // An input method is mid-composition (Japanese, Chinese, accents
            // by dead key). Rewriting attributes now would strip its marked
            // text; the pass that follows the commit picks the styling up.
            guard !textView.hasMarkedText() else { return }
            let text = storage.string
            let nsText = text as NSString
            let length = nsText.length

            let selectedRange = textView.selectedRange()
            let location = min(max(0, selectedRange.location), length)
            let selection = NSRange(location: location, length: min(selectedRange.length, length - location))

            // Literal comparison: Swift's `==` calls canonically equivalent
            // strings equal, and their UTF-16 lengths can differ.
            let textUnchanged = styleCache.map { ($0.source as NSString).isEqual(to: text) } ?? false
            let cache: StyleCache
            if textUnchanged, let styleCache {
                cache = styleCache
            } else {
                cache = StyleCache(source: text)
                styleCache = cache
            }

            let fonts = resolvedFonts()
            let selectionState = MarkdownDocument.SelectionState(
                range: cache.characterOffset(forUTF16: selection.location)
                    ..< cache.characterOffset(forUTF16: NSMaxRange(selection))
            )
            let styled = styledText(cache: cache, selection: selectionState, fonts: fonts)

            // Same text as last time: only the lines the old and new
            // selection touch can have changed (markers hide and reveal by
            // line). Anything else — new text, or attributes that were wiped —
            // compares the whole note.
            var window = NSRange(location: 0, length: length)
            if textUnchanged, let previous = lastStyledSelection, NSMaxRange(previous) <= length {
                // `paragraphRange`, not `lineRange`: the parser's lines end at
                // a newline only, and so must the window.
                window = nsText.paragraphRange(for: NSUnionRange(previous, selection))
            }

            var dirty: [NSRange] = []
            var cursor = window.location
            let windowEnd = NSMaxRange(window)
            while cursor < windowEnd {
                let paragraph = nsText.paragraphRange(for: NSRange(location: cursor, length: 0))
                guard paragraph.length > 0 else { break }
                if !storage.attributedSubstring(from: paragraph)
                    .isEqual(to: styled.attributedSubstring(from: paragraph)) {
                    dirty.append(paragraph)
                }
                cursor = NSMaxRange(paragraph)
            }

            if !dirty.isEmpty {
                storage.beginEditing()
                for paragraph in dirty {
                    styled.enumerateAttributes(in: paragraph, options: []) { attributes, range, _ in
                        storage.setAttributes(attributes, range: range)
                    }
                }
                storage.endEditing()
            }

            lastStyledSelection = selection
            textView.typingAttributes = fonts.defaultAttributes
            if textView.selectedRange() != selection {
                textView.setSelectedRange(selection)
            }
            textView.needsDisplay = true
        }

        private func resolvedFonts() -> EditorFonts {
            if let fonts, fonts.size == parent.fontSize { return fonts }
            let resolved = EditorFonts(size: parent.fontSize)
            fonts = resolved
            return resolved
        }

        /// The whole note with its attributes, detached from any layout.
        private func styledText(
            cache: StyleCache,
            selection: MarkdownDocument.SelectionState,
            fonts: EditorFonts
        ) -> NSMutableAttributedString {
            let document = cache.document
            let styled = NSMutableAttributedString(string: cache.source, attributes: fonts.defaultAttributes)
            guard styled.length > 0 else { return styled }

            let primary = EditorInk.primary
            let secondary = EditorInk.secondary
            let tertiary = EditorInk.tertiary
            let codeWash = EditorInk.codeWash

            // Collapsed: inline delimiters and heading hashes take no room.
            let collapsed: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear,
                .font: fonts.collapsed
            ]
            // Invisible but still occupying its width, so the text after a
            // list or quote prefix does not jump when the caret reveals it.
            let invisible: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear
            ]
            let visibleMarker: [NSAttributedString.Key: Any] = [.font: fonts.body, .foregroundColor: tertiary]
            let visibleMonoMarker: [NSAttributedString.Key: Any] = [.font: fonts.mono, .foregroundColor: tertiary]

            func apply(_ attributes: [NSAttributedString.Key: Any], to range: Range<Int>) {
                guard let nsRange = cache.nsRange(for: range), nsRange.length > 0 else { return }
                styled.addAttributes(attributes, range: nsRange)
            }

            func restyleParagraph(of lineRange: Range<Int>, _ transform: (NSParagraphStyle, Bool) -> NSParagraphStyle) {
                guard let nsRange = cache.nsRange(for: lineRange), nsRange.length > 0 else { return }
                let existing = (styled.attribute(.paragraphStyle, at: nsRange.location, effectiveRange: nil) as? NSParagraphStyle)
                    ?? NSParagraphStyle.default
                styled.addAttribute(.paragraphStyle, value: transform(existing, fonts.isProse), range: nsRange)
            }

            for block in document.blocks {
                switch block.kind {
                case .heading(let heading):
                    let markerAttrs = document.shouldRevealHeading(heading, for: selection) ? visibleMarker : collapsed
                    apply(markerAttrs, to: heading.markerRange)
                    apply(markerAttrs, to: heading.spacingRange)
                    apply([.font: fonts.heading(level: heading.level), .foregroundColor: primary], to: heading.contentRange)

                case .blockquote(let blockquote):
                    for line in blockquote.lines {
                        let reveal = document.shouldRevealPrefix(line.prefixRange, for: selection)
                        apply(reveal ? visibleMarker : invisible, to: line.prefixRange)
                        apply([.foregroundColor: secondary], to: line.contentRange)
                        apply([.groveQuotePrefix: true], to: line.prefixRange)
                        restyleParagraph(of: line.lineRange) { self.quoteParagraphStyle(from: $0, isProse: $1) }
                    }

                case .bulletList(let list):
                    for item in list.items {
                        let reveal = document.shouldRevealPrefix(item.prefixRange, for: selection)
                        apply(reveal ? visibleMarker : invisible, to: item.prefixRange)

                        if let task = item.taskMarker {
                            // The brackets are the marker: no bullet is drawn.
                            apply(
                                [
                                    .font: fonts.mono,
                                    .foregroundColor: task.isChecked ? tertiary : secondary,
                                    .groveTaskMarker: task.isChecked,
                                ],
                                to: task.range
                            )
                            if task.isChecked {
                                apply(
                                    [
                                        .foregroundColor: tertiary,
                                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                    ],
                                    to: item.textRange
                                )
                            }
                        } else {
                            apply([.groveListPrefix: true], to: item.prefixRange)
                        }
                        restyleParagraph(of: item.lineRange) { self.listParagraphStyle(from: $0, isProse: $1) }
                    }

                case .orderedList(let list):
                    // Numbers stay visible (they are the marker), but the line
                    // gets the same indent rhythm as a bullet line.
                    for item in list.items {
                        apply([.font: fonts.mono, .foregroundColor: secondary], to: item.prefixRange)
                        restyleParagraph(of: item.lineRange) { self.listParagraphStyle(from: $0, isProse: $1) }
                    }

                case .codeBlock(let codeBlock):
                    let opening = document.shouldRevealCodeFence(codeBlock.openingFenceRange, for: selection)
                    apply(opening ? visibleMonoMarker : collapsed, to: codeBlock.openingFenceRange)
                    if let closingFenceRange = codeBlock.closingFenceRange {
                        let closing = document.shouldRevealCodeFence(closingFenceRange, for: selection)
                        apply(closing ? visibleMonoMarker : collapsed, to: closingFenceRange)
                    }
                    if let contentRange = codeBlock.contentRange {
                        apply(
                            [.font: fonts.mono, .foregroundColor: primary, .backgroundColor: codeWash],
                            to: contentRange
                        )
                    }

                case .divider:
                    if selection.revealsLine(block.range) {
                        apply(visibleMonoMarker, to: block.range)
                    } else {
                        apply([.foregroundColor: NSColor.clear, .groveDivider: true], to: block.range)
                    }

                case .paragraph:
                    break
                }
            }

            for span in document.inlineSpans {
                let reveal = document.shouldRevealInlineSpan(span, for: selection)
                var isCode = false
                if case .inlineCode = span.kind { isCode = true }

                let markerAttrs: [NSAttributedString.Key: Any]
                if reveal {
                    markerAttrs = isCode
                        ? [.font: fonts.mono, .foregroundColor: tertiary, .backgroundColor: codeWash]
                        : visibleMarker
                } else {
                    markerAttrs = isCode
                        ? collapsed.merging([.backgroundColor: NSColor.clear]) { _, new in new }
                        : collapsed
                }
                for markerRange in span.markerRanges {
                    apply(markerAttrs, to: markerRange)
                }

                guard let contentRange = cache.nsRange(for: span.contentRange), contentRange.length > 0 else { continue }

                switch span.kind {
                case .bold:
                    applyFontTraits(.boldFontMask, to: contentRange, in: styled, fonts: fonts)
                case .italic:
                    applyFontTraits(.italicFontMask, to: contentRange, in: styled, fonts: fonts)
                case .boldItalic:
                    applyFontTraits([.boldFontMask, .italicFontMask], to: contentRange, in: styled, fonts: fonts)
                case .strikethrough:
                    styled.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                case .inlineCode:
                    styled.addAttributes(
                        [.font: fonts.mono, .backgroundColor: codeWash, .foregroundColor: primary],
                        range: contentRange
                    )
                case .wikiLink(let title):
                    styled.addAttributes(
                        [
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: secondary,
                            .groveLink: "wiki:" + title,
                        ],
                        range: contentRange
                    )
                case .link(let url):
                    styled.addAttributes(
                        [
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: secondary,
                            .groveLink: url,
                        ],
                        range: contentRange
                    )
                }
            }

            // Empty delimiter pairs (e.g. the `****` Bold inserts on an empty
            // selection) match no span — dim them so they read as a pending
            // placeholder rather than four literal asterisks.
            for pair in document.emptyMarkerPairs {
                apply(pair.kind == .inlineCode ? visibleMonoMarker : visibleMarker, to: pair.range)
            }

            // The storage substitutes fonts for characters the chosen face
            // lacks (emoji, CJK). Do the same here, or those paragraphs would
            // never compare equal and would be rewritten on every pass.
            styled.fixAttributes(in: NSRange(location: 0, length: styled.length))
            return styled
        }

        private func applyFontTraits(
            _ traits: NSFontTraitMask,
            to nsRange: NSRange,
            in styled: NSMutableAttributedString,
            fonts: EditorFonts
        ) {
            var replacements: [(NSFont, NSRange)] = []
            styled.enumerateAttribute(.font, in: nsRange, options: []) { value, range, _ in
                let baseFont = (value as? NSFont) ?? fonts.body
                var font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)

                // IBM Plex Sans ships no Bold member, so NSFontManager hands the
                // regular face back unchanged. Use the bundled emphasis face
                // instead, which is what the rendered view uses too.
                if traits.contains(.boldFontMask),
                   font.fontName == baseFont.fontName,
                   baseFont.fontName.hasPrefix("IBMPlexSans"),
                   let emphasis = NSFont(name: MarkdownTypeSpec.FontName.bodyEmphasis, size: baseFont.pointSize) {
                    font = traits.contains(.italicFontMask)
                        ? NSFontManager.shared.convert(emphasis, toHaveTrait: .italicFontMask)
                        : emphasis
                }

                replacements.append((font, range))
            }
            for (font, range) in replacements {
                styled.addAttribute(.font, value: font, range: range)
            }
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

        // MARK: - Keyboard

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // An open popup takes the navigation keys before the text does.
            if let key = assistKey(for: commandSelector),
               parent.onAssistKey?(key) == true {
                return true
            }

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
            // Return on an item with nothing in it ends the list: the marker
            // goes, and the caret stays on the now-plain line.
            let markerOnlyRange = NSRange(location: lineRange.location, length: (line as NSString).length)

            if line.count > 1, let listLine = parseListLine(line) {
                let task = taskMarkerPrefix(of: listLine.content)
                let body = task.map { String(listLine.content.dropFirst($0.count)) } ?? listLine.content
                if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    textView.insertText("", replacementRange: markerOnlyRange)
                } else {
                    let nextTask = task == nil ? "" : "[ ] "
                    textView.insertText("\n\(listLine.marker)\(listLine.spacer)\(nextTask)", replacementRange: selected)
                }
                return true
            }
            if let orderedLine = parseOrderedLine(line) {
                let isEmptyItem = orderedLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmptyItem {
                    textView.insertText("", replacementRange: markerOnlyRange)
                } else {
                    textView.insertText(
                        "\n\(orderedLine.indent)\(orderedLine.number + 1)\(orderedLine.delimiter)\(orderedLine.spacer)",
                        replacementRange: selected
                    )
                }
                return true
            }
            if let quoteLine = parseQuoteLine(line) {
                let isEmptyQuote = quoteLine.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmptyQuote {
                    textView.insertText("", replacementRange: markerOnlyRange)
                } else {
                    textView.insertText("\n>\(quoteLine.spacer)", replacementRange: selected)
                }
                return true
            }
            return false
        }

        private func assistKey(for commandSelector: Selector) -> EditorAssistKey? {
            if commandSelector == #selector(NSResponder.moveDown(_:)) { return .down }
            if commandSelector == #selector(NSResponder.moveUp(_:)) { return .up }
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertTab(_:)) {
                return .commit
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { return .cancel }
            return nil
        }

        /// `[ ] ` / `[x] ` at the start of a list item's content, or the bare
        /// marker when nothing follows it yet.
        private func taskMarkerPrefix(of content: String) -> String? {
            for marker in ["[ ]", "[x]", "[X]"] {
                if content == marker { return marker }
                if content.hasPrefix(marker + " ") { return marker + " " }
            }
            return nil
        }

        private func parseOrderedLine(
            _ line: String
        ) -> (indent: String, number: Int, delimiter: String, spacer: String, content: String)? {
            MarkdownLineParsing.orderedLine(line)
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

// MARK: - Style Cache

/// A parse of the note plus the table that turns the parser's offsets into
/// the text view's.
///
/// `MarkdownDocument` counts in characters; NSTextStorage counts in UTF-16
/// units. They agree until the first emoji. Converting by walking the string
/// from its start for every range made styling quadratic in the length of the
/// note, so the table is built once per text change and each conversion is a
/// lookup.
private struct StyleCache {
    let source: String
    let document: MarkdownDocument
    /// `utf16Offsets[i]` is the UTF-16 offset of character `i`; the final
    /// entry is the length of the text.
    private let utf16Offsets: [Int]

    init(source: String) {
        self.source = source
        document = MarkdownDocument(source)

        var offsets: [Int] = []
        offsets.reserveCapacity(source.utf16.count + 1)
        var offset = 0
        for character in source {
            offsets.append(offset)
            offset += character.utf16.count
        }
        offsets.append(offset)
        utf16Offsets = offsets
    }

    func nsRange(for characterRange: Range<Int>) -> NSRange? {
        guard characterRange.lowerBound >= 0,
              characterRange.upperBound < utf16Offsets.count else { return nil }
        let lower = utf16Offsets[characterRange.lowerBound]
        let upper = utf16Offsets[characterRange.upperBound]
        return NSRange(location: lower, length: upper - lower)
    }

    /// The character a UTF-16 offset falls in (or sits in front of).
    func characterOffset(forUTF16 location: Int) -> Int {
        var low = 0
        var high = utf16Offsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if utf16Offsets[mid] <= location {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

// MARK: - Editor Fonts

/// The faces and default attributes for one body size, resolved once: styling
/// runs on every keystroke, and stable instances keep the attribute diff exact.
private struct EditorFonts {
    let size: CGFloat
    let body: NSFont
    let mono: NSFont
    /// A 0.1pt face: hidden delimiters keep their characters but lose their width.
    let collapsed: NSFont
    let defaultAttributes: [NSAttributedString.Key: Any]
    private let headingLarge: NSFont
    private let headingMedium: NSFont
    private let headingSmall: NSFont

    /// The note writer and reflections set prose at 18pt with generous
    /// leading; the boxed editor does not.
    var isProse: Bool { size >= 17 }

    @MainActor
    init(size: CGFloat) {
        self.size = size
        let monoSize = MarkdownTypeSpec.monoSize(forBodySize: size)
        let body = NSFont(name: MarkdownTypeSpec.FontName.body, size: size) ?? NSFont.systemFont(ofSize: size)
        self.body = body
        mono = NSFont(name: MarkdownTypeSpec.FontName.mono, size: monoSize)
            ?? NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular)
        collapsed = NSFont.systemFont(ofSize: 0.1)

        func heading(_ level: Int) -> NSFont {
            let headingSize = MarkdownTypeSpec.headingSize(forLevel: level, bodySize: size)
            return NSFont(name: MarkdownTypeSpec.FontName.heading, size: headingSize)
                ?? NSFont.systemFont(ofSize: headingSize, weight: .medium)
        }
        headingLarge = heading(1)
        headingMedium = heading(2)
        headingSmall = heading(3)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: body,
            .foregroundColor: EditorInk.primary,
        ]
        if size >= 17 {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = MarkdownTypeSpec.proseLineSpacing
            style.paragraphSpacing = MarkdownTypeSpec.proseParagraphSpacing
            attributes[.paragraphStyle] = style
        }
        defaultAttributes = attributes
    }

    /// Levels 4–6 share the largest face, as they always have here.
    func heading(level: Int) -> NSFont {
        switch level {
        case 2: return headingMedium
        case 3: return headingSmall
        default: return headingLarge
        }
    }
}

// MARK: - HighlightingTextView

/// Custom NSTextView subclass: formatting shortcuts, the drawn parts of the
/// markdown (bullets, quote rails, dividers), and the clicks that act on it
/// (task checkboxes, ⌘-click on links).
class HighlightingTextView: NSTextView {
    static weak var focusedEditor: HighlightingTextView?

    var onFocusChange: ((Bool) -> Void)?
    /// ⌘-click on a link: `wiki:<title>` or a URL string.
    var onOpenLink: ((String) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMarkdownQuoteRails(in: dirtyRect)
        drawMarkdownListBullets(in: dirtyRect)
        drawMarkdownDividers(in: dirtyRect)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            Self.focusedEditor = self
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            if Self.focusedEditor === self {
                Self.focusedEditor = nil
            }
            onFocusChange?(false)
        }
        return resigned
    }

    // MARK: - Clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(under: point), let storage = textStorage {
            // A click on `[ ]` / `[x]` ticks the task instead of moving the caret.
            var markerRange = NSRange(location: 0, length: 0)
            if storage.attribute(
                .groveTaskMarker,
                at: index,
                longestEffectiveRange: &markerRange,
                in: NSRange(location: 0, length: storage.length)
            ) is Bool, markerRange.length == 3 {
                toggleTaskMarker(in: markerRange)
                return
            }

            if event.modifierFlags.contains(.command),
               let target = storage.attribute(.groveLink, at: index, effectiveRange: nil) as? String {
                onOpenLink?(target)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// The character whose glyph is under `point`, or nil when the point is
    /// in a margin or past the end of a line.
    private func characterIndex(under point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.contains(containerPoint) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return index < textStorage.length ? index : nil
    }

    private func toggleTaskMarker(in markerRange: NSRange) {
        guard let textStorage, markerRange.length == 3 else { return }
        let stateRange = NSRange(location: markerRange.location + 1, length: 1)
        let isChecked = (textStorage.string as NSString).substring(with: stateRange) != " "
        let replacement = isChecked ? " " : "x"
        if shouldChangeText(in: stateRange, replacementString: replacement) {
            textStorage.replaceCharacters(in: stateRange, with: replacement)
            didChangeText()
        }
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
        let markerColor = EditorInk.secondary
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
        let railColor = EditorInk.rule
        let baseSize = font?.pointSize ?? 15
        // Matches the 2pt rule the rendered view draws beside a quote.
        let railWidth: CGFloat = baseSize >= 17 ? 2.0 : 1.5
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

    /// A hidden `---` line is drawn as a hairline across the measure. With
    /// the caret on the line the dashes show instead, so it can be edited.
    private func drawMarkdownDividers(in dirtyRect: NSRect) {
        guard
            let storage = textStorage,
            let layoutManager = layoutManager,
            let textContainer = textContainer,
            storage.length > 0
        else { return }

        let textOrigin = textContainerOrigin
        let padding = textContainer.lineFragmentPadding
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(.groveDivider, in: fullRange, options: []) { value, range, _ in
            guard let isDivider = value as? Bool, isDivider, range.length > 0 else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { return }

            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let ruleRect = NSRect(
                x: textOrigin.x + lineRect.minX + padding,
                y: (textOrigin.y + lineRect.midY).rounded() - 0.5,
                width: max(0, lineRect.width - padding * 2),
                height: 1
            )
            guard ruleRect.intersects(dirtyRect) else { return }

            EditorInk.rule.setFill()
            ruleRect.fill()
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

        var replacementRange = NSRange(location: openRange.location, length: safeCursor - openRange.location)
        // The toolbar's "Link to an Item" types the closing pair too and
        // leaves the caret between the two. Take that pair with the query, or
        // the pick would read `[[Title]]]]`.
        if nsText.substring(from: safeCursor).hasPrefix("]]") {
            replacementRange.length += 2
        }
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

    /// Swaps the `/query` in front of the caret for the markdown a block
    /// command stands for.
    func replaceActiveSlashQuery(with insertion: String, cursorOffset: Int = 0) {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0, let textStorage else { return }

        let nsText = string as NSString
        let caret = min(selectedRange.location, nsText.length)
        let lineStart = nsText.lineRange(for: NSRange(location: caret, length: 0)).location
        let linePrefix = nsText.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard let detected = EditorAssistTrigger.detect(linePrefix: linePrefix),
              detected.trigger.isSlash,
              detected.tokenLength <= caret - lineStart else { return }

        let replacementRange = NSRange(location: caret - detected.tokenLength, length: detected.tokenLength)
        let insertedLength = (insertion as NSString).length

        if shouldChangeText(in: replacementRange, replacementString: insertion) {
            textStorage.replaceCharacters(in: replacementRange, with: insertion)
            didChangeText()
            let end = replacementRange.location + insertedLength
            let cursor = min(max(end + cursorOffset, replacementRange.location), end)
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
    /// A host that needs to reach the caret passes its own proxy.
    var proxy: MarkdownEditingProxy? = nil
    /// Accepted for parity with macOS, which shows it in the toolbar; the
    /// iOS editor has no such toolbar.
    var status: String? = nil
    /// Accepted for parity with macOS (⌘-click on a wiki link).
    var onNavigateToItem: ((Item) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]

    @State private var ownedProxy = MarkdownEditingProxy()
    private var editingProxy: MarkdownEditingProxy { proxy ?? ownedProxy }
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
                        .padding(.bottom, Spacing.xsm)
                }

                MarkdownUITextView(
                    text: $text,
                    minHeight: minHeight,
                    fontSize: proseMode ? MarkdownTypeSpec.proseBodySize : 16,
                    textInset: proseMode
                        ? UIEdgeInsets(top: 8, left: 20, bottom: 24, right: 20)
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
                    .padding(.horizontal, Spacing.xs)

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
                    .padding(.horizontal, Spacing.xs)

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
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
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
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.xsm)
            .padding(.bottom, Spacing.xs)

            Divider()

            if wikiSearchResults.isEmpty {
                Text("No matching items")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(Spacing.sm)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(wikiSearchResults) { candidate in
                            Button {
                                insertWikiLink(for: candidate)
                            } label: {
                                HStack(spacing: Spacing.xsm) {
                                    Image(systemName: candidate.type.iconName)
                                        .font(.groveBadge)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 14)
                                    Text(candidate.title)
                                        .font(.groveBodySmall)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, Spacing.xs)
                                .padding(.horizontal, Spacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
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
