import SwiftUI
import SwiftData

// MARK: - List Model

/// One row of the Library list: an item, and how this row presents it.
/// The index lists each item once; find results may list an item again
/// under another heading (once for its title, once for a reflection on it).
struct LibraryListRow: Identifiable {
    /// Unique per row, not per item.
    let id: String
    /// The item the row selects and opens.
    let item: Item
    /// The word in the type column ("Article", "Note", "Reflect."), and
    /// what assistive technology reads for the type in either theme.
    let typeLabel: String
    /// The glyph the type column shows in the Grove theme, in place of the
    /// item type's own. Set for reflection rows; nil for item rows.
    let typeSymbolName: String?
    /// A note the user wrote: its type is set in stronger ink.
    let isOwn: Bool
    /// The line under the title, around the match. Nil in the index.
    let snippet: LibraryFind.Snippet?
    /// The date at the right of the row.
    let date: Date
    /// False under a month heading, which already carries the year.
    let dateCarriesYear: Bool
    let showsBoard: Bool
}

/// A board the find field matched, offered as a row that applies that
/// board's filter chip.
struct LibraryBoardRow: Identifiable {
    /// Unique among all rows of the list.
    let id: String
    let board: Board
}

/// A run of rows under one heading: a month of the index, or a group of
/// find results. With no title the rows are listed without a heading.
/// The Boards group has `boardRows` and no `rows`; every other section the
/// reverse.
struct LibraryListSection: Identifiable {
    let id: String
    let title: String?
    /// Set beside the heading as a badge. Nil for months.
    let count: Int?
    let rows: [LibraryListRow]
    var boardRows: [LibraryBoardRow] = []
}

extension Array where Element == LibraryListSection {
    /// Every row's ID in display order: what the keyboard highlight moves through.
    var rowIDs: [String] {
        flatMap { section in section.boardRows.map(\.id) + section.rows.map(\.id) }
    }
}

// MARK: - Keyboard Highlight

/// The row Down and Up have moved to from the find field, if any.
///
/// A reference, so that moving the highlight redraws the list and not the
/// whole page: `LibraryView` writes it from its key handlers without reading
/// it in its body, and only `LibraryListView` reads it.
@MainActor
@Observable
final class LibraryFindCursor {
    var highlightedRowID: String?
}

// MARK: - Library List View

/// The Library's list: the index by month, or the grouped find results.
/// Selection, multi-select, the row menu and the hover action are the same
/// for both.
struct LibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sections: [LibraryListSection]
    /// What to say when there are no sections.
    let emptyState: LibraryEmptyState
    /// A quiet line set above the first heading, when there is something
    /// to say about the rows as a whole.
    let leadLine: String?
    let isMultiSelectMode: Bool
    let selectedIDs: Set<UUID>
    /// The keyboard highlight the find field moves.
    let cursor: LibraryFindCursor
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    let onToggleSelection: (Item) -> Void
    let onEnterMultiSelect: (Item) -> Void
    let onDeleteRequest: (Item) -> Void
    /// A board row was chosen: apply that board's filter chip.
    let onApplyBoard: (Board) -> Void

    var body: some View {
        if sections.isEmpty {
            emptyView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let leadLine {
                            quietLine(leadLine)
                                .padding(.top, Spacing.lg)
                        }
                        ForEach(sections) { section in
                            if let title = section.title {
                                sectionHeader(title: title, count: section.count)
                            }
                            ForEach(section.boardRows) { boardRow in
                                boardRowView(for: boardRow)
                                    .id(boardRow.id)
                                if boardRow.id != section.boardRows.last?.id {
                                    rowRule
                                }
                            }
                            ForEach(section.rows) { row in
                                selectableRow(for: row)
                                    .id(row.id)
                                if row.id != section.rows.last?.id {
                                    rowRule
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.lg)
                    if isMultiSelectMode && !selectedIDs.isEmpty {
                        Spacer().frame(height: LibraryMetrics.actionBarClearance)
                    }
                }
                .onChange(of: cursor.highlightedRowID) { _, newValue in
                    guard let newValue else { return }
                    if reduceMotion {
                        proxy.scrollTo(newValue)
                    } else {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(newValue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Headings

    /// A heading over a run of rows: the month, or the kind of match with
    /// its count.
    private func sectionHeader(title: String, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title)
                .sectionHeaderStyle()
                .lineLimit(1)

            if let count {
                Text("\(count)")
                    .font(.groveBadge)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, Spacing.xsm)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.tag)
                            .fill(Color.accentBadge)
                            .padding(.vertical, -LibraryMetrics.badgeInsetV)
                    }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var rowRule: some View {
        Rectangle()
            .fill(Color.borderPrimary)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.groveGhostText)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Selectable Row

    /// True when the keyboard highlight is on a row of the list. While it
    /// is, it alone is lit, rather than the selected item as well.
    private var hasKeyboardHighlight: Bool {
        guard let highlighted = cursor.highlightedRowID else { return false }
        return sections.rowIDs.contains(highlighted)
    }

    private func selectableRow(for row: LibraryListRow) -> some View {
        let item = row.item
        let isItemSelected = selectedIDs.contains(item.id)
        let isHighlighted: Bool
        if isMultiSelectMode {
            isHighlighted = isItemSelected || cursor.highlightedRowID == row.id
        } else if hasKeyboardHighlight {
            isHighlighted = cursor.highlightedRowID == row.id
        } else {
            isHighlighted = selectedItem?.id == item.id
        }

        return HStack(spacing: 0) {
            if isMultiSelectMode {
                Image(systemName: isItemSelected ? "checkmark.circle.fill" : "circle")
                    .font(.groveBody)
                    .foregroundStyle(isItemSelected ? Color.textPrimary : Color.textMuted)
                    .frame(width: 28)
                    .padding(.leading, Spacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
            LibraryRowView(row: row)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            handleRowTap(item: item)
        }
        .selectedItemStyle(isHighlighted)
        .contextMenu {
            rowContextMenu(for: item)
        }
    }

    private func handleRowTap(item: Item) {
        if isMultiSelectMode {
            withAnimation(.easeInOut(duration: 0.1)) {
                onToggleSelection(item)
            }
            return
        }
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.command) {
            onEnterMultiSelect(item)
            return
        }
        #endif
        selectedItem = item
        openedItem = item
    }

    // MARK: - Board Row

    private func boardRowView(for boardRow: LibraryBoardRow) -> some View {
        LibraryBoardRowView(board: boardRow.board)
            .contentShape(Rectangle())
            .onTapGesture {
                onApplyBoard(boardRow.board)
            }
            .selectedItemStyle(cursor.highlightedRowID == boardRow.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Board \(boardRow.board.title)")
            .accessibilityHint("Shows only this board's items.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onApplyBoard(boardRow.board)
            }
    }

    @ViewBuilder
    private func rowContextMenu(for item: Item) -> some View {
        Button {
            openedItem = item
            selectedItem = item
        } label: {
            Label("Open", systemImage: "doc.text")
        }
        Button {
            NotificationCenter.default.postDiscussItem(DiscussItemPayload(item: item))
        } label: {
            Label("Discuss", systemImage: "bubble.left.and.bubble.right")
        }
        Divider()
        Button {
            toggleArchive(for: item)
        } label: {
            Label(item.status == .archived ? "Unarchive" : "Archive",
                  systemImage: item.status == .archived ? "tray.and.arrow.up" : "archivebox")
        }
        Button("Delete Item", role: .destructive) {
            onDeleteRequest(item)
        }
    }

    /// Archive an active item, or restore an archived one to active.
    private func toggleArchive(for item: Item) {
        let archiving = item.status != .archived
        item.status = archiving ? .archived : .active
        item.updatedAt = .now
        if archiving {
            if selectedItem?.id == item.id { selectedItem = nil }
            if openedItem?.id == item.id { openedItem = nil }
        }
        try? modelContext.save()
    }

    // MARK: - Empty State

    /// Set at the top of the page on the list's margin, where the first
    /// heading would be.
    private var emptyView: some View {
        Group {
            switch emptyState {
            case .searching:
                quietLine("Searching\u{2026}")
                    .padding(.vertical, Spacing.xl)
            case .message(let title, let detail):
                GroveEmptyState(title: title, detail: detail)
            }
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Library Row View

/// One line of the index: type, title, board, date. A find result adds a
/// second line, the snippet around its match, and gives up the board.
struct LibraryRowView: View {
    let row: LibraryListRow
    @State private var isHovered = false
    @ScaledMetric(relativeTo: .caption) private var typeColumnWidth: CGFloat = LibraryMetrics.typeColumnWidth
    @ScaledMetric(relativeTo: .caption) private var typeGlyphColumnWidth: CGFloat = LibraryMetrics.typeGlyphColumnWidth
    @ScaledMetric(relativeTo: .caption) private var dateColumnMinWidth: CGFloat = LibraryMetrics.dateColumnMinWidth

    private var item: Item { row.item }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            typeLabel
            titleAndSnippet

            // Discuss button — visible on hover
            if isHovered {
                discussButton
            }

            if row.showsBoard {
                boardLabel
            }
            dateLabel
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    /// The type, marked the theme's way: a glyph in Grove, a word in mono
    /// capitals in Commonplace. A note of the user's own is set in stronger ink.
    private var typeLabel: some View {
        ItemTypeMark(
            type: item.type,
            label: row.typeLabel,
            emphasized: row.isOwn,
            symbolName: row.typeSymbolName
        )
        .frame(
            width: ThemeStore.shared.theme.usesGlyphs ? typeGlyphColumnWidth : typeColumnWidth,
            alignment: .leading
        )
    }

    private var titleAndSnippet: some View {
        VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            Text(item.title)
                .font(.groveListTitle)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            if let snippet = row.snippet {
                snippetLine(snippet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The snippet on one line, its match marked by weight and ink. The
    /// lead-in is short, so the match stays in view when the tail is cut.
    private func snippetLine(_ snippet: LibraryFind.Snippet) -> some View {
        let match: Text = Text(snippet.match)
            .font(.groveSnippetMatch)
            .foregroundStyle(Color.textPrimary)

        return Text("\(Text(snippet.before))\(match)\(Text(snippet.after))")
            .font(.groveBodySecondary)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var discussButton: some View {
        Button {
            NotificationCenter.default.postDiscussItem(DiscussItemPayload(item: item))
        } label: {
            Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Spacing.sm)
                // The chip is drawn past the label's own height, so showing
                // it on hover does not change the height of the row.
                .background {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(Color.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                        .padding(.vertical, -LibraryMetrics.badgeInsetV)
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .transition(.opacity)
    }

    private var boardLabel: some View {
        Text(LibraryIndex.boardLabel(item.boards.first?.title))
            .font(.groveMeta)
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
            .fixedSize()
    }

    private var dateLabel: some View {
        Text(LibraryIndex.dateLabel(for: row.date, carriesYear: row.dateCarriesYear))
            .font(.groveMeta)
            .monospacedDigit()
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: dateColumnMinWidth, alignment: .trailing)
    }
}

// MARK: - Library Board Row View

/// A board the find field matched: its mark, its name, and what choosing it
/// does. Set on the same columns as an item row.
struct LibraryBoardRowView: View {
    let board: Board
    @ScaledMetric(relativeTo: .caption) private var typeColumnWidth: CGFloat = LibraryMetrics.typeColumnWidth
    @ScaledMetric(relativeTo: .caption) private var typeGlyphColumnWidth: CGFloat = LibraryMetrics.typeGlyphColumnWidth

    var body: some View {
        let usesGlyphs = ThemeStore.shared.theme.usesGlyphs

        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Group {
                if usesGlyphs {
                    Image(systemName: "folder")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                } else {
                    Text("Board")
                        .sectionHeaderStyle()
                        .lineLimit(1)
                }
            }
            .frame(width: usesGlyphs ? typeGlyphColumnWidth : typeColumnWidth, alignment: .leading)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs / 2) {
                Text(board.title)
                    .font(.groveListTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text("Show only this board")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Date Extension

extension Date {
    var relativeShort: String {
        let now = Date()
        let diff = now.timeIntervalSince(self)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
