import SwiftUI

// MARK: - Focus Request

extension Notification.Name {
    /// Puts the keyboard in the Library's find field. Posted by the window;
    /// observed by `LibraryFindField`, which exists only while the Library
    /// page is on screen. No object, no userInfo.
    ///
    /// A bare post made before the page is mounted is not seen. A window that
    /// has to bring the Library on screen first posts through
    /// `NotificationCenter.postFocusLibrarySearch()`, which also leaves the
    /// request for a field that mounts a moment later.
    static let groveFocusLibrarySearch = Notification.Name("groveFocusLibrarySearch")
}

extension NotificationCenter {
    /// Posts `groveFocusLibrarySearch` and remembers the request briefly, so
    /// that it still lands when the Library page is only now coming on screen
    /// (the window has just switched to it, or closed the reader over it).
    @MainActor
    func postFocusLibrarySearch() {
        LibraryFindFocusRequest.madeAt = .now
        post(name: .groveFocusLibrarySearch, object: nil)
    }
}

/// A focus request the find field has not acted on yet.
@MainActor
private enum LibraryFindFocusRequest {
    static var madeAt: Date?

    /// How long a request waits for the page to mount before it lapses.
    static let grace: TimeInterval = 1

    /// True, once, if a request was made within the grace period.
    static func take() -> Bool {
        guard let requestedAt = madeAt else { return false }
        madeAt = nil
        return Date.now.timeIntervalSince(requestedAt) < grace
    }
}

// MARK: - Find Field

/// The Library's find field: always on the page, searching as you type.
/// It owns the text and the keyboard focus only; `LibraryView` runs the search.
struct LibraryFindField: View {
    @Binding var query: String
    /// Rows the list is showing for the query. Nil shows no count.
    let resultCount: Int?
    /// Return was pressed in the field.
    let onSubmit: () -> Void
    /// Down (1) or Up (-1) was pressed in the field: move the highlight
    /// through the rows. The field keeps the keyboard throughout.
    let onMoveHighlight: (Int) -> Void

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = LibraryMetrics.findFieldHeight

    private let placeholder = "Find in the library"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)

            TextField(
                "",
                text: $query,
                prompt: Text(placeholder)
                    .font(.groveBody)
                    .foregroundStyle(Color.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.groveBody)
            .foregroundStyle(Color.textPrimary)
            .focused($isFocused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .onSubmit { onSubmit() }
            #if os(macOS)
            // Esc empties the field; pressed again, it gives the keyboard back.
            .onExitCommand { handleEscape() }
            #endif
            .accessibilityLabel(placeholder)

            if let resultCount {
                Text(LibraryFind.countLabel(resultCount))
                    .font(.groveMeta)
                    .monospacedDigit()
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
                    .fixedSize()
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                        .padding(Spacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .accessibilityHint("Empties the find field and shows the whole library.")
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: fieldHeight)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(isFocused ? Color.borderInput : Color.borderPrimary, lineWidth: 1)
        )
        // Down and Up while the field has the keyboard, as in the search
        // overlay: they move the list's highlight, and the text stays put.
        .onKeyPress(.downArrow) {
            onMoveHighlight(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            onMoveHighlight(-1)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveFocusLibrarySearch)) { _ in
            LibraryFindFocusRequest.madeAt = nil
            isFocused = true
        }
        .onAppear {
            // A request made while the page was on its way in. Focus has to
            // wait a turn for the field to be in the window, as in the overlay.
            guard LibraryFindFocusRequest.take() else { return }
            Task { @MainActor in
                await Task.yield()
                isFocused = true
            }
        }
    }

    private func handleEscape() {
        if query.isEmpty {
            isFocused = false
        } else {
            query = ""
        }
    }
}

// MARK: - Sort Menu

/// The sort order, set as a quiet mono label that opens the three options.
struct LibrarySortMenu: View {
    @Binding var sortOption: LibrarySortOption

    var body: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(LibrarySortOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Text("\(sortOption.label) \u{2193}")
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Sort: \(sortOption.label)")
    }
}

// MARK: - Board Filter

/// Horizontal board chip filter bar for the library. It carries no side
/// inset of its own: the Library's header sets it on the page margin.
struct LibraryBoardFilterBar: View {
    let boards: [Board]
    @Binding var selectedBoardID: UUID?
    @Binding var showingArchived: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // "All" chip
                boardChip(title: "All", boardID: nil)

                ForEach(boards) { board in
                    boardChip(title: board.title, boardID: board.id)
                }

                Divider()
                    .frame(height: 16)

                archivedChip
            }
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.bgPrimary)
    }

    /// Toggle chip that switches the list to archived items.
    private var archivedChip: some View {
        FilterChip(label: "Archived", systemImage: "archivebox", isActive: showingArchived) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showingArchived.toggle()
            }
        }
        .help(showingArchived ? "Show active items" : "Show archived items")
    }

    private func boardChip(title: String, boardID: UUID?) -> some View {
        FilterChip(label: title, isActive: selectedBoardID == boardID) {
            selectedBoardID = boardID
        }
    }
}
