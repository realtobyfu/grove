import SwiftUI
import SwiftData

/// Custom sidebar column: a field-style search control up top, quiet nav
/// rows with soft monochrome selection, a BOARDS section with drag
/// reorder, and a pinned Settings footer. Window chrome (sidebar toggle,
/// traffic lights) is left to the system so full screen behaves.
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var showNewBoardSheet = false
    @State private var boardToEdit: Board?
    @State private var boardToDelete: Board?
    @State private var isBoardsHeaderHovered = false

    /// Personal captures only — newsletter issues have their own unread count.
    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox && !$0.isFeedSuggestion }.count
    }

    private var unreadNewsletterCount: Int {
        allItems.filter {
            $0.isNewsletterIssue && $0.status != .dismissed && !$0.isFeedIssueRead
        }.count
    }

    private var viewModel: BoardViewModel {
        BoardViewModel(modelContext: modelContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    searchField
                        .padding(.bottom, Spacing.md)

                    SidebarRow(
                        icon: "sun.max",
                        title: "Today",
                        count: inboxCount,
                        isSelected: selection == .home
                    ) { selection = .home }

                    SidebarRow(
                        icon: "books.vertical",
                        title: "Library",
                        isSelected: selection == .library
                    ) { selection = .library }

                    SidebarRow(
                        icon: "newspaper",
                        title: "Newsletters",
                        count: unreadNewsletterCount,
                        isSelected: selection == .newsletters
                    ) { selection = .newsletters }

                    boardsHeader
                        .padding(.top, Spacing.xl)
                        .padding(.bottom, Spacing.xs)

                    ForEach(boards) { board in
                        boardRow(board)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }

            footer
        }
        .background(Color.bgSidebar)
        #if os(macOS)
        // Keep the column one continuous flat surface up into the titlebar
        // (no system toolbar material band above the content).
        .toolbarBackground(.hidden, for: .windowToolbar)
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .groveNewBoard)) { _ in
            showNewBoardSheet = true
        }
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon, color, nudgeFreq in
                    viewModel.createBoard(title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                }
            )
        }
        .sheet(item: $boardToEdit) { board in
            BoardEditorSheet(
                board: board,
                onSave: { title, icon, color, nudgeFreq in
                    viewModel.updateBoard(board, title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                }
            )
        }
        .alert(
            "Delete Board",
            isPresented: Binding(
                get: { boardToDelete != nil },
                set: { if !$0 { boardToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                boardToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let board = boardToDelete {
                    viewModel.deleteBoard(board)
                    if case .board(let id) = selection, id == board.id {
                        selection = nil
                    }
                }
                boardToDelete = nil
            }
        } message: {
            if let board = boardToDelete {
                Text("Are you sure you want to delete \"\(board.title)\"? Items in this board will not be deleted.")
            }
        }
    }

    // MARK: - Search

    /// Field-styled search control: bordered and filled so it reads as an
    /// input, not a stray glyph. Opens the search overlay.
    private var searchField: some View {
        SidebarSearchField {
            NotificationCenter.default.post(name: .groveToggleSearch, object: nil)
        }
    }

    // MARK: - Boards

    private var boardsHeader: some View {
        HStack(spacing: Spacing.sm) {
            Text("Boards")
                .sectionHeaderStyle()

            Spacer()

            Button {
                showNewBoardSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isBoardsHeaderHovered ? 1 : 0.5)
            .help("New Board")
            .accessibilityLabel("New board")
            .accessibilityHint("Create a board in the sidebar list.")
        }
        .padding(.horizontal, Spacing.sm)
        .onHover { isBoardsHeaderHovered = $0 }
        .contextMenu {
            Button("New Board...") {
                showNewBoardSheet = true
            }
        }
    }

    private func boardRow(_ board: Board) -> some View {
        SidebarRow(
            icon: board.icon ?? "folder",
            iconColor: board.color.map { Color(hex: $0) },
            title: board.title,
            tier: .board,
            isSelected: selection == .board(board.id)
        ) { selection = .board(board.id) }
            .contextMenu {
                Button("Edit Board...") {
                    boardToEdit = board
                }
                Divider()
                Button("Delete Board", role: .destructive) {
                    boardToDelete = board
                }
            }
            .draggable(board.id.uuidString)
            .dropDestination(for: String.self) { droppedIDs, _ in
                moveBoard(droppedIDs: droppedIDs, before: board)
            }
    }

    /// Drag-to-reorder replacement for List's onMove: drop a board row onto
    /// another to insert it at that position.
    private func moveBoard(droppedIDs: [String], before target: Board) -> Bool {
        guard let idString = droppedIDs.first,
              let sourceID = UUID(uuidString: idString),
              sourceID != target.id,
              let sourceIndex = boards.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = boards.firstIndex(where: { $0.id == target.id }) else { return false }
        // IndexSet/offset semantics match List.onMove.
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        viewModel.moveBoard(from: IndexSet(integer: sourceIndex), to: destination, in: boards)
        return true
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        #if os(macOS)
        SettingsFooterRow()
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        #endif
    }
}

// MARK: - Search Field

/// Bordered, filled control shaped like a search input. A button in
/// disguise: clicking opens the search overlay.
private struct SidebarSearchField: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)

                Text("Search")
                    .font(.groveBodySecondary)
                    .foregroundStyle(isHovering ? Color.textSecondary : Color.textTertiary)

                Spacer(minLength: Spacing.sm)

                Text("⌘K")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.sm + 2)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .help("Search (⌘K)")
        .accessibilityLabel("Search")
    }
}

// MARK: - Sidebar Row

/// One nav row. Selection is a soft rounded card fill — a quiet button,
/// clearly tappable — with ink darkening for hover, in the app's
/// monochrome voice. Counts sit right-aligned like page numbers, joined
/// by a dotted leader.
///
/// Two tiers establish hierarchy: `.primary` (Today/Library/Newsletters)
/// reads as chapters — medium weight, full size; `.board` reads as
/// sub-entries — slightly smaller, indented one step.
private struct SidebarRow: View {
    enum Tier {
        case primary, board
    }

    let icon: String
    var iconColor: Color? = nil
    let title: String
    var count: Int = 0
    var tier: Tier = .primary
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var inkColor: Color {
        isSelected || isHovering ? Color.textPrimary : Color.textSecondary
    }

    private var fillColor: Color {
        if isSelected { return Color.bgCard }
        if isHovering { return Color.bgCardHover.opacity(0.6) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            // Baseline alignment: symbols carry a text baseline, so icon,
            // label, and count sit on one line instead of box-centering.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: tier == .primary ? 13 : 12, weight: .medium))
                    .foregroundStyle(iconColor ?? inkColor)
                    .frame(width: 20)

                Text(title)
                    .font(tier == .primary ? .groveBodyMedium : .groveBodySecondary)
                    .foregroundStyle(inkColor)
                    .lineLimit(1)
                    .layoutPriority(1) // labels win over the dotted leader

                if count > 0 {
                    TOCLeader()
                        .frame(minWidth: Spacing.sm)

                    Text("\(count)")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Spacer(minLength: Spacing.sm)
                }
            }
            .padding(.leading, tier == .board ? Spacing.lg : Spacing.sm + 2)
            .padding(.trailing, Spacing.sm + 2)
            .frame(minHeight: tier == .primary ? 32 : 30)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The dotted line between a TOC entry and its page number. Echoes the
/// dashed borders of auto-tags — same ink, different sentence.
private struct TOCLeader: View {
    var body: some View {
        LeaderLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .foregroundStyle(Color.borderTagDashed)
            // In a baseline-aligned HStack a shape aligns by its bottom
            // edge, which lands the leader right on the text baseline.
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct LeaderLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }
    }
}

#if os(macOS)
/// Pinned Settings row — same quiet-button voice as the nav rows.
private struct SettingsFooterRow: View {
    @State private var isHovering = false

    var body: some View {
        SettingsLink {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20)

                Text("Settings")
                    .font(.groveBodySecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? Color.textPrimary : Color.textTertiary)
            .padding(.horizontal, Spacing.sm + 2)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.bgCardHover.opacity(0.6) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
#endif
