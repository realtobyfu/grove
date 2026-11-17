import SwiftUI

// MARK: - Focus Request

extension Notification.Name {
    /// Puts the keyboard in the Library's find field. Posted by the window;
    /// observed by `LibraryFindField`, which exists only while the Library
    /// page is on screen. A post made before the page is mounted is not seen,
    /// so a window that has to switch to the Library first posts on the next
    /// main-actor turn. No object, no userInfo.
    static let groveFocusLibrarySearch = Notification.Name("groveFocusLibrarySearch")
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
        .onReceive(NotificationCenter.default.publisher(for: .groveFocusLibrarySearch)) { _ in
            isFocused = true
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
