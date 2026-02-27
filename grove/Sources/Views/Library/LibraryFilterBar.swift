import SwiftUI

/// Search bar for the library with text field and multi-select toggle.
struct LibrarySearchBar: View {
    @Binding var searchQuery: String
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // "All" chip
                boardChip(title: "All", boardID: nil)

                ForEach(boards) { board in
                    boardChip(title: board.title, boardID: board.id)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.bgPrimary)
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

/// Revisit banner shown when spaced-repetition items are overdue.
struct LibraryRevisitBanner: View {
    let overdueCount: Int
    @Binding var showingRevisitFilter: Bool
    @Binding var selectedBoardID: UUID?
    @Binding var searchQuery: String

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                showingRevisitFilter.toggle()
                if showingRevisitFilter {
                    selectedBoardID = nil
                    searchQuery = ""
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                Text("\(overdueCount) item\(overdueCount == 1 ? "" : "s") to revisit")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if showingRevisitFilter {
                    Text("Show all")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                Image(systemName: showingRevisitFilter ? "xmark" : "chevron.right")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(showingRevisitFilter ? Color.bgCard : Color.bgPrimary)
        }
        .buttonStyle(.plain)
    }
}
