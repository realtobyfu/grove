import SwiftUI
import SwiftData

/// A note, as a page.
///
/// The note sits in the detail column at the reading measure: a dateline in
/// mono, the title in Newsreader as the head of the page, then the prose. The
/// rail beside it stays free — for chat, or for the inspector, where the
/// note's connections and backlinks live.
///
/// Nothing here is "saved" by the reader: the page writes itself to the store
/// a moment after typing pauses, and says so in the folio line.
struct NotePageView: View {
    let item: Item
    /// The note was created empty a moment ago by "New Note". Leaving it with
    /// nothing in it removes it again.
    var isFresh: Bool = false
    var onNavigateToItem: ((Item) -> Void)? = nil
    /// Brings up the inspector (connections, backlinks, boards, tags).
    var onShowLinks: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var draft = NoteDraft()
    @State private var editorProxy = MarkdownEditingProxy()
    @FocusState private var isTitleFocused: Bool

    /// The editor insets its text by the writing gutter on both sides, so the
    /// column is the measure plus the two gutters and the prose itself runs
    /// at exactly `proseMeasure`.
    private var columnWidth: CGFloat {
        RightRailMetrics.proseMeasure + LayoutDimensions.writingGutter * 2
    }

    var body: some View {
        ReaderMeasureColumn(measure: columnWidth) {
            VStack(alignment: .leading, spacing: 0) {
                dateline
                titleField
                RichMarkdownEditor(
                    text: $draft.content,
                    sourceItem: item,
                    minHeight: 240,
                    proseMode: true,
                    proxy: editorProxy,
                    status: draft.state.label,
                    onNavigateToItem: onNavigateToItem
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgPrimary)
        .onAppear {
            draft.configure(item: item, boardID: nil, modelContext: modelContext, isFresh: isFresh)
            // A blank page starts at its title; a written one is left alone
            // until the reader clicks into it.
            if !draft.hasText { isTitleFocused = true }
        }
        .onDisappear {
            draft.finish()
        }
        .onChange(of: draft.title) { draft.textDidChange() }
        .onChange(of: draft.content) { draft.textDidChange() }
        #if os(macOS)
        // Quitting does not run `onDisappear`.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            draft.finish()
        }
        #endif
    }

    // MARK: - Dateline

    /// NOTE · 17 NOV 2026 · BOARD on the left; the note's links on the right.
    private var dateline: some View {
        HStack(spacing: Spacing.sm) {
            Text(datelineText)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            if let onShowLinks {
                Button(action: onShowLinks) {
                    Text(linksText)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show connections and backlinks")
                .accessibilityLabel("Show connections and backlinks. \(linksText)")
            }
        }
        .font(.groveFolio)
        .textCase(.uppercase)
        .tracking(0.8)
        .foregroundStyle(Color.textMuted)
        .padding(.horizontal, LayoutDimensions.writingGutter)
        .padding(.top, LayoutDimensions.contentPaddingTop)
        .padding(.bottom, Spacing.lg)
    }

    private var datelineText: String {
        var parts = ["Note", item.createdAt.formatted(.dateTime.day().month(.abbreviated).year())]
        let boardNames = item.boards.map(\.title).filter { !$0.isEmpty }.sorted()
        if let first = boardNames.first {
            parts.append(boardNames.count > 1 ? "\(first) +\(boardNames.count - 1)" : first)
        }
        return parts.joined(separator: "  \u{00B7}  ")
    }

    private var linksText: String {
        let outgoing = item.outgoingConnections.count
        let incoming = item.incomingConnections.count
        if outgoing == 0 && incoming == 0 { return "No links yet" }
        var parts: [String] = []
        if outgoing > 0 { parts.append("\(outgoing) \(outgoing == 1 ? "link" : "links")") }
        if incoming > 0 { parts.append("\(incoming) \(incoming == 1 ? "backlink" : "backlinks")") }
        return parts.joined(separator: "  \u{00B7}  ")
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("", text: $draft.title, prompt:
            Text("Untitled")
                .foregroundStyle(Color.textMuted)
        )
        .textFieldStyle(.plain)
        .font(.groveTitle)
        .foregroundStyle(Color.textPrimary)
        .focused($isTitleFocused)
        // Return in the title carries on into the body.
        .onSubmit { editorProxy.focus() }
        .padding(.horizontal, LayoutDimensions.writingGutter)
        .padding(.bottom, Spacing.md)
        .accessibilityLabel("Note title")
    }
}
