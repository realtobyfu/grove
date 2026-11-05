import SwiftUI

/// Search bar for the library with text field, sort menu, and multi-select toggle.
struct LibrarySearchBar: View {
    @Binding var searchQuery: String
    @Binding var sortOption: LibrarySortOption
    let isSearching: Bool
    let isMultiSelectMode: Bool
    let onToggleMultiSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
        .padding(.vertical, 10)
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
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                showingArchived.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "archivebox")
                    .font(.groveMeta)
                Text("Archived")
                    .font(.groveTag)
            }
            .foregroundStyle(showingArchived ? Color.textInverse : Color.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(showingArchived ? Color.bgTagActive : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(showingArchived ? Color.clear : Color.borderTag, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(showingArchived ? "Show active items" : "Show archived items")
    }

    private func boardChip(title: String, boardID: UUID?) -> some View {
        let isActive = selectedBoardID == boardID
        return Button {
            selectedBoardID = boardID
        } label: {
            Text(title)
                .font(.groveTag)
                .foregroundStyle(isActive ? Color.textInverse : Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.bgTagActive : Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
