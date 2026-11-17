import SwiftUI

/// Search bar for the library with text field, sort menu, and multi-select toggle.
struct LibrarySearchBar: View {
    @Binding var searchQuery: String
    @Binding var sortOption: LibrarySortOption
    let isSearching: Bool
    let isMultiSelectMode: Bool
    let onToggleMultiSelect: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isSearching ? "hourglass" : "magnifyingglass")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .animation(.easeInOut(duration: 0.15), value: isSearching)

            TextField("Search titles, content, tags, reflections\u{2026}", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Sort order menu
            Menu {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Sort: \(sortOption.label)")

            // Select mode toggle
            Button {
                onToggleMultiSelect()
            } label: {
                Text(isMultiSelectMode ? "Cancel" : "Select")
                    .font(.groveBodySmall)
                    .foregroundStyle(isMultiSelectMode ? Color.textPrimary : Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(Color.bgPrimary)
    }
}

/// Horizontal board chip filter bar for the library.
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
            .padding(.horizontal, Spacing.md)
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
