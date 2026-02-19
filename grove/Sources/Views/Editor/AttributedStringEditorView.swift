import SwiftUI
import SwiftData

// MARK: - AttributedStringEditorView

/// A macOS 26+ text editor that uses SwiftUI's native TextEditor(text:selection:)
/// with AttributedString for rich markdown editing with selection-aware formatting.
@available(macOS 26, *)
struct AttributedStringEditorView: View {
    @Binding var markdownText: String
    var sourceItem: Item?
    var proseMode: Bool = false
    var minHeight: CGFloat = 80

    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]

    @State private var attributedText: AttributedString = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var suppressAttributedUpdates = false
    @State private var suppressMarkdownUpdates = false
    @State private var serializationTask: Task<Void, Never>?

    // Wiki-link autocomplete
    @State private var showWikiPopover = false
    @State private var wikiSearchText = ""
    @State private var wikiReplacementOffsets: Range<Int>?

    private let converter = MarkdownAttributedStringConverter()
    private var formatting: GroveFormattingDefinition {
        GroveFormattingDefinition(fontSize: proseMode ? 18 : 15)
    }

    private var wikiSearchResults: [Item] {
        allItems.filter { candidate in
            if let sourceItem, candidate.id == sourceItem.id { return false }
            if wikiSearchText.isEmpty { return true }
            return candidate.title.localizedStandardContains(wikiSearchText)
        }.prefix(10).map { $0 }
    }

    private var plainText: String {
        String(attributedText.characters)
    }

    private var wordCountLabel: String {
        let wordCount = plainText.split { $0.isWhitespace || $0.isNewline }.count
        return "\(wordCount) \(wordCount == 1 ? "Word" : "Words")"
    }

    var body: some View {
        editorContent
            .onAppear {
                reloadFromMarkdown(markdownText, preserveSelection: false)
            }
            .onChange(of: markdownText) { _, newValue in
                guard !suppressMarkdownUpdates else { return }
                reloadFromMarkdown(newValue, preserveSelection: true)
            }
            .onChange(of: attributedText) { _, _ in
                guard !suppressAttributedUpdates else { return }
                detectWikiLink()
                scheduleSerializeToMarkdown()
            }
            .onDisappear {
                serializationTask?.cancel()
            }
    }

    @ViewBuilder
    private var editorContent: some View {
        if proseMode {
            proseLayout
        } else {
            standardLayout
        }
    }

    private var standardLayout: some View {
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

            editorField
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
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

    private var proseLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(wordCountLabel)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 4)

            editorField
                .lineSpacing(8)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .frame(minHeight: minHeight)

            if showWikiPopover {
                wikiLinkDropdown
                    .padding(.horizontal, 40)
            }

            proseCommandBar
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
        }
    }

    private var editorField: some View {
        TextEditor(text: $attributedText, selection: $selection)
            .font(formatting.bodyFont)
            .textEditorStyle(.plain)
            .writingToolsBehavior(.limited)
            .writingToolsAffordanceVisibility(.automatic)
    }

    // MARK: - Sync

    private func scheduleSerializeToMarkdown() {
        serializationTask?.cancel()
        let latest = plainText
        serializationTask = Task { @MainActor [latest] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard markdownText != latest else { return }
            suppressMarkdownUpdates = true
            markdownText = latest
            suppressMarkdownUpdates = false
        }
    }

    private func reloadFromMarkdown(
        _ markdown: String,
        preserveSelection: Bool,
        preferredSelection: SelectionOffsets? = nil
    ) {
        let targetSelection: SelectionOffsets
        if let preferredSelection {
            targetSelection = preferredSelection
        } else if preserveSelection {
            targetSelection = currentSelectionOffsets(in: attributedText)
        } else {
            targetSelection = SelectionOffsets(start: markdown.count, end: markdown.count)
        }

        suppressAttributedUpdates = true
        attributedText = converter.attributedString(from: markdown)
        formatting.applyPresentation(to: &attributedText)
        selection = makeSelection(from: targetSelection, in: attributedText)
        suppressAttributedUpdates = false
        detectWikiLink()
    }

    private func commitMarkdown(_ markdown: String, selection targetSelection: SelectionOffsets) {
        serializationTask?.cancel()

        suppressMarkdownUpdates = true
        if markdownText != markdown {
            markdownText = markdown
        }
        suppressMarkdownUpdates = false

        reloadFromMarkdown(markdown, preserveSelection: false, preferredSelection: targetSelection)
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            toolbarButton("Bold", icon: "bold", shortcut: "B") { wrapSelection(prefix: "**", suffix: "**") }
            toolbarButton("Italic", icon: "italic", shortcut: "I") { wrapSelection(prefix: "*", suffix: "*") }
            toolbarButton("Code", icon: "chevron.left.forwardslash.chevron.right", shortcut: "E") { wrapSelection(prefix: "`", suffix: "`") }
            toolbarButton("Strikethrough", icon: "strikethrough", shortcut: nil) { wrapSelection(prefix: "~~", suffix: "~~") }

            Divider().frame(height: 16).padding(.horizontal, 4)

            Menu {
                Button("# Title") { setHeading(level: 1) }
                Button("## Heading") { setHeading(level: 2) }
                Button("### Subheading") { setHeading(level: 3) }
                Divider()
                Button("Clear Heading") { setHeading(level: 0) }
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

            toolbarButton("Quote", icon: "text.quote", shortcut: nil) { toggleBlockQuote() }
            toolbarButton("List", icon: "list.bullet", shortcut: nil) { toggleListItem() }

            Divider().frame(height: 16).padding(.horizontal, 4)

            toolbarButton("Link", icon: "link", shortcut: "K") { insertLink() }
            toolbarButton("Wiki Link", icon: "link.badge.plus", shortcut: nil) { insertWikiLinkSyntax() }

            Spacer()
            Text(wordCountLabel)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var proseCommandBar: some View {
        HStack(spacing: 18) {
            proseCommandButton("### Subheading") { setHeading(level: 3) }
            proseCommandButton("- List") { toggleListItem() }
            proseCommandButton("> Quote") { toggleBlockQuote() }

            Menu {
                Button("# Title") { setHeading(level: 1) }
                Button("## Heading") { setHeading(level: 2) }
                Button("### Subheading") { setHeading(level: 3) }
                Button("Clear Heading") { setHeading(level: 0) }
                Divider()
                Button("Bold") { wrapSelection(prefix: "**", suffix: "**") }
                Button("Italic") { wrapSelection(prefix: "*", suffix: "*") }
                Button("Inline Code") { wrapSelection(prefix: "`", suffix: "`") }
                Button("Strikethrough") { wrapSelection(prefix: "~~", suffix: "~~") }
                Divider()
                Button("Link") { insertLink() }
                Button("Wiki Link") { insertWikiLinkSyntax() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.bgCard)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.borderInput, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.borderInput.opacity(0.45), lineWidth: 1)
        )
    }

    private func proseCommandButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.groveBodyLarge)
                .foregroundStyle(Color.textSecondary)
        }
        .buttonStyle(.plain)
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

    // MARK: - Formatting Actions

    private func wrapSelection(prefix: String, suffix: String) {
        mutateMarkdown { markdown, selection in
            let startIndex = markdownIndex(in: markdown, offset: selection.start)
            let endIndex = markdownIndex(in: markdown, offset: selection.end)
            let selectedText = String(markdown[startIndex..<endIndex])

            if !selection.isInsertionPoint,
               selectedText.hasPrefix(prefix),
               selectedText.hasSuffix(suffix),
               selectedText.count >= prefix.count + suffix.count {
                let innerStart = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
                let innerEnd = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
                let unwrapped = String(selectedText[innerStart..<innerEnd])
                markdown.replaceSubrange(startIndex..<endIndex, with: unwrapped)
                selection.end = selection.start + unwrapped.count
                return
            }

            let replacement = prefix + selectedText + suffix
            markdown.replaceSubrange(startIndex..<endIndex, with: replacement)

            if selection.isInsertionPoint {
                let caretOffset = selection.start + prefix.count
                selection.start = caretOffset
                selection.end = caretOffset
            } else {
                selection.start += prefix.count
                selection.end = selection.start + selectedText.count
            }
        }
    }

    private func insertLink() {
        mutateMarkdown { markdown, selection in
            let startIndex = markdownIndex(in: markdown, offset: selection.start)
            let endIndex = markdownIndex(in: markdown, offset: selection.end)
            let selectedText = String(markdown[startIndex..<endIndex])
            let replacement: String

            if selectedText.isEmpty {
                replacement = "[](url)"
                selection.start += 1
                selection.end = selection.start
            } else {
                replacement = "[\(selectedText)](url)"
                let urlStart = selection.start + selectedText.count + 3
                selection.start = urlStart
                selection.end = urlStart + 3
            }

            markdown.replaceSubrange(startIndex..<endIndex, with: replacement)
        }
    }

    private func insertWikiLinkSyntax() {
        insertSnippet("[[]]", cursorOffset: -2)
    }

    private func insertSnippet(_ snippet: String, cursorOffset: Int) {
        mutateMarkdown { markdown, selection in
            let startIndex = markdownIndex(in: markdown, offset: selection.start)
            let endIndex = markdownIndex(in: markdown, offset: selection.end)
            markdown.replaceSubrange(startIndex..<endIndex, with: snippet)

            let minCaret = selection.start
            let maxCaret = selection.start + snippet.count
            let proposed = selection.start + snippet.count + cursorOffset
            let clamped = min(max(proposed, minCaret), maxCaret)
            selection.start = clamped
            selection.end = clamped
        }
    }

    private func toggleBlockQuote() {
        toggleLinePrefix("> ")
    }

    private func toggleListItem() {
        toggleLinePrefix("- ")
    }

    private func setHeading(level: Int) {
        let clampedLevel = min(max(level, 0), 6)
        let prefix = clampedLevel > 0 ? String(repeating: "#", count: clampedLevel) + " " : ""

        mutateMarkdown { markdown, selection in
            let lineOffsets = selectedLineOffsets(in: markdown, selection: selection)
            let blockStart = markdownIndex(in: markdown, offset: lineOffsets.lowerBound)
            let blockEnd = markdownIndex(in: markdown, offset: lineOffsets.upperBound)

            let lines = String(markdown[blockStart..<blockEnd]).components(separatedBy: "\n")
            let transformed = lines.map { line -> String in
                guard !line.isEmpty else { return line }
                return prefix + lineRemovingHeadingPrefix(line)
            }

            let replaced = transformed.joined(separator: "\n")
            markdown.replaceSubrange(blockStart..<blockEnd, with: replaced)

            if selection.isInsertionPoint {
                let newCaret = min(lineOffsets.lowerBound + prefix.count, lineOffsets.lowerBound + replaced.count)
                selection.start = newCaret
                selection.end = newCaret
            } else {
                selection.start = lineOffsets.lowerBound
                selection.end = lineOffsets.lowerBound + replaced.count
            }
        }
    }

    private func toggleLinePrefix(_ prefix: String) {
        mutateMarkdown { markdown, selection in
            let lineOffsets = selectedLineOffsets(in: markdown, selection: selection)
            let blockStart = markdownIndex(in: markdown, offset: lineOffsets.lowerBound)
            let blockEnd = markdownIndex(in: markdown, offset: lineOffsets.upperBound)

            let lines = String(markdown[blockStart..<blockEnd]).components(separatedBy: "\n")
            let nonEmptyLines = lines.filter { !$0.isEmpty }
            let shouldRemovePrefix = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { $0.hasPrefix(prefix) }

            let transformed = lines.map { line -> String in
                guard !line.isEmpty else { return line }
                if shouldRemovePrefix {
                    return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
                }
                return prefix + line
            }

            let replaced = transformed.joined(separator: "\n")
            markdown.replaceSubrange(blockStart..<blockEnd, with: replaced)

            if selection.isInsertionPoint {
                let newCaret = min(
                    lineOffsets.lowerBound + (shouldRemovePrefix ? 0 : prefix.count),
                    lineOffsets.lowerBound + replaced.count
                )
                selection.start = newCaret
                selection.end = newCaret
            } else {
                selection.start = lineOffsets.lowerBound
                selection.end = lineOffsets.lowerBound + replaced.count
            }
        }
    }

    private func lineRemovingHeadingPrefix(_ line: String) -> String {
        var index = line.startIndex
        var hashCount = 0
        while index < line.endIndex && line[index] == "#" && hashCount < 6 {
            hashCount += 1
            index = line.index(after: index)
        }

        guard hashCount > 0, index < line.endIndex, line[index] == " " else {
            return line
        }

        let contentStart = line.index(after: index)
        return String(line[contentStart...])
    }

    // MARK: - Selection Helpers

    private func mutateMarkdown(_ mutation: (inout String, inout SelectionOffsets) -> Void) {
        var markdown = plainText
        var targetSelection = currentSelectionOffsets(in: attributedText)
        let originalMarkdown = markdown
        let originalSelection = targetSelection

        mutation(&markdown, &targetSelection)

        guard markdown != originalMarkdown || targetSelection != originalSelection else {
            return
        }

        commitMarkdown(markdown, selection: targetSelection)
    }

    private func currentSelectionOffsets(in text: AttributedString) -> SelectionOffsets {
        switch selection.indices(in: text) {
        case .insertionPoint(let point):
            let offset = text.characters.distance(from: text.startIndex, to: point)
            return SelectionOffsets(start: offset, end: offset)
        case .ranges(let ranges):
            guard let first = ranges.ranges.first else {
                return SelectionOffsets(start: 0, end: 0)
            }
            let last = ranges.ranges.last ?? first
            let start = text.characters.distance(from: text.startIndex, to: first.lowerBound)
            let end = text.characters.distance(from: text.startIndex, to: last.upperBound)
            return SelectionOffsets(start: start, end: end)
        }
    }

    private func makeSelection(from offsets: SelectionOffsets, in text: AttributedString) -> AttributedTextSelection {
        var clamped = offsets
        clamped.clamp(to: text.characters.count)
        let start = text.index(text.startIndex, offsetByCharacters: clamped.start)
        let end = text.index(text.startIndex, offsetByCharacters: clamped.end)
        if clamped.isInsertionPoint {
            return AttributedTextSelection(insertionPoint: start)
        }
        return AttributedTextSelection(range: start..<end)
    }

    private func selectedLineOffsets(in markdown: String, selection: SelectionOffsets) -> Range<Int> {
        let lineStart = lineStartOffset(in: markdown, at: selection.start)
        let endAnchor: Int
        if selection.end > selection.start {
            endAnchor = max(selection.start, selection.end - 1)
        } else {
            endAnchor = selection.end
        }
        let lineEnd = lineEndOffset(in: markdown, at: endAnchor)
        return lineStart..<lineEnd
    }

    private func lineStartOffset(in markdown: String, at offset: Int) -> Int {
        let clamped = min(max(offset, 0), markdown.count)
        let cursor = markdownIndex(in: markdown, offset: clamped)
        let prefix = markdown[..<cursor]
        let start = prefix.lastIndex(of: "\n").map { markdown.index(after: $0) } ?? markdown.startIndex
        return markdown.distance(from: markdown.startIndex, to: start)
    }

    private func lineEndOffset(in markdown: String, at offset: Int) -> Int {
        let clamped = min(max(offset, 0), markdown.count)
        let cursor = markdownIndex(in: markdown, offset: clamped)
        let suffix = markdown[cursor...]
        let end = suffix.firstIndex(of: "\n") ?? markdown.endIndex
        return markdown.distance(from: markdown.startIndex, to: end)
    }

    private func markdownIndex(in markdown: String, offset: Int) -> String.Index {
        let clamped = min(max(offset, 0), markdown.count)
        return markdown.index(markdown.startIndex, offsetBy: clamped)
    }

    // MARK: - Wiki Link Detection

    private func caretOffsetIfInsertionPoint() -> Int? {
        switch selection.indices(in: attributedText) {
        case .insertionPoint(let point):
            return attributedText.characters.distance(from: attributedText.startIndex, to: point)
        case .ranges(let ranges):
            guard let first = ranges.ranges.first, ranges.ranges.count == 1, first.isEmpty else {
                return nil
            }
            return attributedText.characters.distance(from: attributedText.startIndex, to: first.lowerBound)
        }
    }

    private func closeWikiPopover() {
        if showWikiPopover {
            showWikiPopover = false
        }
        wikiSearchText = ""
        wikiReplacementOffsets = nil
    }

    private func detectWikiLink() {
        guard let caretOffset = caretOffsetIfInsertionPoint() else {
            closeWikiPopover()
            return
        }

        let text = plainText
        let caretIndex = markdownIndex(in: text, offset: caretOffset)
        let prefix = text[..<caretIndex]

        guard let openRange = prefix.range(of: "[[", options: .backwards) else {
            closeWikiPopover()
            return
        }

        let queryRange = openRange.upperBound..<caretIndex
        let query = String(text[queryRange])

        if query.contains("]]") || query.contains("\n") {
            closeWikiPopover()
            return
        }

        let replacementStart = text.distance(from: text.startIndex, to: openRange.lowerBound)
        wikiReplacementOffsets = replacementStart..<caretOffset
        wikiSearchText = query
        showWikiPopover = true
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
        var markdown = plainText
        let replacement = "[[\(target.title)]]"
        let replacementOffsets = wikiReplacementOffsets ?? (markdown.count..<markdown.count)
        let lower = markdownIndex(in: markdown, offset: replacementOffsets.lowerBound)
        let upper = markdownIndex(in: markdown, offset: replacementOffsets.upperBound)
        markdown.replaceSubrange(lower..<upper, with: replacement)
        let caret = replacementOffsets.lowerBound + replacement.count
        closeWikiPopover()
        commitMarkdown(markdown, selection: SelectionOffsets(start: caret, end: caret))

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

    private struct SelectionOffsets: Equatable {
        var start: Int
        var end: Int

        var isInsertionPoint: Bool {
            start == end
        }

        mutating func clamp(to characterCount: Int) {
            start = min(max(0, start), characterCount)
            end = min(max(start, end), characterCount)
        }
    }
}
