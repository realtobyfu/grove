import SwiftUI

/// The one board picker.
///
/// Replaces the old `SmartBoardPickerSheet` and the hand-rolled "Move to
/// Board" list in the library. Print/TOC idiom throughout: no color dots,
/// board glyph and title in ink, item count right-aligned in mono like a
/// page number, hover darkens the ink, and keyboard focus draws a 2pt left
/// rule instead of filling the row.
///
/// Two modes:
/// - `.add` appends board membership (inbox triage, capture, reader FAB).
/// - `.move` replaces membership and offers an explicit "Unfiled" target
///   (library multi-select).
struct BoardPickerView: View {
    enum Mode {
        /// Append the chosen board to the item's existing boards.
        case add
        /// Replace membership with the chosen board (or clear it via Unfiled).
        case move
    }

    /// How the picker is being presented. Popovers drop the title block and
    /// the Skip button — the anchor already says what the picker is for.
    enum Chrome {
        case sheet
        case popover
    }

    let boards: [Board]
    var mode: Mode = .add
    var chrome: Chrome = .sheet
    /// Name proposed by the suggestion engine — seeds the "Create" row.
    var suggestedName: String = ""
    var recommendedBoardID: UUID? = nil
    var alternativeBoardIDs: [UUID] = []
    var onSelect: (Board) -> Void
    var onCreate: ((String) -> Void)? = nil
    /// `.move` only: clear board membership entirely.
    var onSelectUnfiled: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var focusedIndex = 0
    @FocusState private var searchFocused: Bool

    // MARK: - Entries

    private enum Entry: Identifiable {
        case unfiled
        case board(Board)
        case create(String)

        var id: String {
            switch self {
            case .unfiled: "unfiled"
            case .board(let board): board.id.uuidString
            case .create(let name): "create:\(name)"
            }
        }
    }

    private struct EntrySection: Identifiable {
        let id: String
        let title: String?
        let entries: [Entry]
    }

    // MARK: - Derived state

    private var normalizedSuggestedName: String {
        BoardSuggestionEngine.cleanedBoardName(suggestedName)
    }

    private var normalizedQuery: String {
        BoardSuggestionEngine.cleanedBoardName(query)
    }

    private var boardNameCandidate: String {
        let candidate = normalizedQuery.isEmpty ? normalizedSuggestedName : normalizedQuery
        return BoardSuggestionEngine.cleanedBoardName(candidate)
    }

    private var exactExistingBoard: Board? {
        guard !boardNameCandidate.isEmpty else { return nil }
        return boards.first { $0.title.localizedCaseInsensitiveCompare(boardNameCandidate) == .orderedSame }
    }

    private var canCreateBoard: Bool {
        onCreate != nil && !boardNameCandidate.isEmpty && exactExistingBoard == nil
    }

    private var rankedBoards: [Board] {
        let filtered: [Board]
        if normalizedQuery.isEmpty {
            filtered = boards
        } else {
            filtered = boards.filter { board in
                board.title.localizedStandardContains(normalizedQuery)
                    || (board.boardDescription?.localizedStandardContains(normalizedQuery) ?? false)
            }
        }
        return filtered
            .map { board in
                (board: board, score: BoardRanking.rank(
                    board,
                    recommendedBoardID: recommendedBoardID,
                    prioritizedBoardIDs: alternativeBoardIDs,
                    suggestedName: normalizedSuggestedName,
                    query: normalizedQuery
                ))
            }
            .sorted { $0.score > $1.score }
            .map(\.board)
    }

    /// The board pinned into the BEST MATCH section, when it survives the search filter.
    private var bestMatchBoard: Board? {
        guard let recommendedBoardID else { return nil }
        return rankedBoards.first { $0.id == recommendedBoardID }
    }

    private var sections: [EntrySection] {
        var result: [EntrySection] = []

        if mode == .move, onSelectUnfiled != nil, normalizedQuery.isEmpty {
            result.append(EntrySection(id: "unfiled", title: nil, entries: [.unfiled]))
        }

        if let bestMatchBoard {
            result.append(EntrySection(id: "best", title: "Best match", entries: [.board(bestMatchBoard)]))
        }

        let rest = rankedBoards.filter { $0.id != bestMatchBoard?.id }
        if !rest.isEmpty {
            result.append(EntrySection(
                id: "boards",
                title: bestMatchBoard == nil ? nil : "All boards",
                entries: rest.map(Entry.board)
            ))
        }

        if canCreateBoard {
            result.append(EntrySection(id: "create", title: nil, entries: [.create(boardNameCandidate)]))
        }

        return result
    }

    private var flatEntries: [Entry] {
        sections.flatMap(\.entries)
    }

    private var headerTitle: String {
        switch mode {
        case .add: "Assign to board"
        case .move: "Move to board"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chrome == .sheet {
                titleBlock
            }

            searchField

            Divider()

            entryList

            if chrome == .sheet {
                Divider()
                footer
            }
        }
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        #if os(macOS)
        .frame(width: chrome == .sheet ? 380 : 320, height: chrome == .sheet ? 440 : 380)
        #else
        // iPad presents .popover chrome as a real popover, which would size
        // to intrinsic content around an unbounded ScrollView. Sheets take
        // their size from the presentation, so only popover needs a frame.
        .frame(
            width: chrome == .popover ? 320 : nil,
            height: chrome == .popover ? 420 : nil
        )
        #endif
        .onAppear {
            focusedIndex = initialFocusIndex
            searchFocused = true
        }
        .onChange(of: query) { _, _ in focusedIndex = initialFocusIndex }
        .onKeyPress(.upArrow) { moveFocus(by: -1) }
        .onKeyPress(.downArrow) { moveFocus(by: 1) }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headerTitle)
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)

            if !normalizedSuggestedName.isEmpty {
                Text("Suggested: \(normalizedSuggestedName)")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)

            TextField(
                onCreate == nil ? "Search boards" : "Search boards, or type a new name",
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.groveBody)
            .foregroundStyle(Color.textPrimary)
            .focused($searchFocused)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            #endif
            .onSubmit { activateFocusedEntry() }
            // The search field holds focus, so it sees the arrows first —
            // handle them here too or the field editor swallows them.
            .onKeyPress(.upArrow) { moveFocus(by: -1) }
            .onKeyPress(.downArrow) { moveFocus(by: 1) }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if flatEntries.isEmpty {
                        emptyState
                    } else {
                        let indexed = indexedSections()
                        ForEach(indexed, id: \.section.id) { pair in
                            if let title = pair.section.title {
                                Text(title)
                                    .sectionHeaderStyle()
                                    .padding(.horizontal, Spacing.lg)
                                    .padding(.top, Spacing.md)
                                    .padding(.bottom, Spacing.xs)
                            }

                            ForEach(Array(pair.section.entries.enumerated()), id: \.element.id) { offset, entry in
                                row(for: entry, index: pair.startIndex + offset)
                                    .id(pair.startIndex + offset)
                            }
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .onChange(of: focusedIndex) { _, index in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        Text("No matching boards")
            .font(.groveBodySecondary)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.xxl)
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            #if os(macOS)
            Text("\u{2191}\u{2193} move  \u{21A9} select  esc close")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
            #endif

            Spacer(minLength: Spacing.sm)

            // In .move mode nothing is being skipped — the honest verb is
            // Cancel. .add keeps Skip: the item stays deliberately unfiled.
            Button(mode == .move ? "Cancel" : "Skip") { dismiss() }
                .buttonStyle(.plain)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    /// First focus target: never the Unfiled row. Return-to-move-everything-
    /// to-Unfiled is destructive enough to require a deliberate arrow-up or
    /// click, so focus starts on the first actual board.
    private var initialFocusIndex: Int {
        let entries = flatEntries
        if let firstBoard = entries.firstIndex(where: {
            if case .board = $0 { return true } else { return false }
        }) {
            return firstBoard
        }
        return 0
    }

    @ViewBuilder
    private func row(for entry: Entry, index: Int) -> some View {
        switch entry {
        case .unfiled:
            BoardPickerRow(
                glyph: "tray",
                title: "Unfiled",
                count: nil,
                isFocused: index == focusedIndex,
                action: { activate(entry) }
            )
        case .board(let board):
            BoardPickerRow(
                glyph: board.icon ?? "folder",
                title: board.title,
                count: board.items.count,
                isFocused: index == focusedIndex,
                action: { activate(entry) }
            )
        case .create(let name):
            BoardPickerRow(
                glyph: "plus",
                title: "Create \u{201C}\(name)\u{201D}",
                count: nil,
                isFocused: index == focusedIndex,
                action: { activate(entry) }
            )
        }
    }

    // MARK: - Layout helpers

    private struct IndexedSection {
        let section: EntrySection
        let startIndex: Int
    }

    private func indexedSections() -> [IndexedSection] {
        var running = 0
        var result: [IndexedSection] = []
        for section in sections {
            result.append(IndexedSection(section: section, startIndex: running))
            running += section.entries.count
        }
        return result
    }

    // MARK: - Actions

    private func moveFocus(by offset: Int) -> KeyPress.Result {
        let entries = flatEntries
        guard !entries.isEmpty else { return .ignored }
        focusedIndex = max(0, min(entries.count - 1, focusedIndex + offset))
        return .handled
    }

    private func activateFocusedEntry() {
        let entries = flatEntries
        guard focusedIndex >= 0, focusedIndex < entries.count else { return }
        activate(entries[focusedIndex])
    }

    private func activate(_ entry: Entry) {
        switch entry {
        case .unfiled:
            onSelectUnfiled?()
        case .board(let board):
            onSelect(board)
        case .create(let name):
            onCreate?(name)
        }
        dismiss()
    }
}

// MARK: - Row

/// One line of the table of contents: glyph, title, page-number count.
/// Hover darkens the ink; focus adds a 2pt left rule. Never a filled row.
private struct BoardPickerRow: View {
    let glyph: String
    let title: String
    let count: Int?
    let isFocused: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var isEmphasized: Bool { isFocused || isHovering }

    private var titleInk: Color { isEmphasized ? Color.textPrimary : Color.textSecondary }
    private var metaInk: Color { isEmphasized ? Color.textSecondary : Color.textTertiary }

    #if os(iOS)
    private var rowHeight: CGFloat { LayoutDimensions.minTouchTarget }
    #else
    private var rowHeight: CGFloat { 30 }
    #endif

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: glyph)
                    .font(.groveBodySmall)
                    .foregroundStyle(metaInk)
                    .frame(width: 16)

                Text(title)
                    .font(.groveBody)
                    .foregroundStyle(titleInk)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                if let count {
                    Text("\(count)")
                        .font(.groveMeta)
                        .monospacedDigit()
                        .foregroundStyle(metaInk)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.textPrimary)
                    .frame(width: 2)
                    .opacity(isFocused ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.sm)
        .onHover { isHovering = $0 }
        .accessibilityLabel(count.map { "\(title), \($0) items" } ?? title)
    }
}

// MARK: - Ranking

/// Board ordering heuristic, lifted out of the old SmartBoardPickerSheet so
/// every picker surface ranks the same way.
enum BoardRanking {
    static func rank(
        _ board: Board,
        recommendedBoardID: UUID?,
        prioritizedBoardIDs: [UUID],
        suggestedName: String,
        query: String
    ) -> Double {
        var score = 0.0

        if board.id == recommendedBoardID {
            score += 100
        }

        if let index = prioritizedBoardIDs.firstIndex(of: board.id) {
            score += Double(max(0, 60 - (index * 10)))
        }

        if !suggestedName.isEmpty,
           board.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame {
            score += 70
        }

        if !query.isEmpty {
            let queryLower = query.lowercased()
            let titleLower = board.title.lowercased()
            if titleLower == queryLower {
                score += 70
            } else if titleLower.hasPrefix(queryLower) {
                score += 45
            } else if board.title.localizedStandardContains(query) {
                score += 25
            }

            if let description = board.boardDescription,
               description.localizedStandardContains(query) {
                score += 8
            }
        }

        score += min(Double(board.items.count), 20)

        return score
    }

    /// Boards worth offering as one-click chips for an item: the recommended
    /// board first, then the engine's alternates.
    static func suggestedBoards(
        for item: Item,
        from boards: [Board],
        limit: Int = 3
    ) -> [Board] {
        let decision = BoardSuggestionMetadata.decision(from: item)
        var orderedIDs: [UUID] = []
        if let recommended = decision?.recommendedBoardID {
            orderedIDs.append(recommended)
        }
        for id in decision?.alternativeBoardIDs ?? [] where !orderedIDs.contains(id) {
            orderedIDs.append(id)
        }

        var result: [Board] = orderedIDs.compactMap { id in
            boards.first { $0.id == id }
        }

        // Fall back to the plain name suggestion when the engine only left a title.
        if result.isEmpty {
            let name = decision?.suggestedName ?? item.suggestedBoard ?? ""
            if !name.isEmpty,
               let matched = boards.first(where: {
                   $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
               }) {
                result = [matched]
            }
        }

        return Array(result.prefix(limit))
    }
}
