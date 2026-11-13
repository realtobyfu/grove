#if os(macOS)
import AppKit
#endif
import SwiftUI

/// Extracted from BoardDetailView — toolbar cluster, empty state, and suggestions bar.
@MainActor
struct BoardDetailHeaderView {
    let board: Board
    /// The board's active items in the order they are currently displayed.
    let displayedItems: [Item]
    let boardDiscussionSuggestions: [PromptBubble]
    let sortOption: BoardSortOption

    @Binding var viewMode: BoardViewMode
    @Binding var sortOptionBinding: BoardSortOption
    @Binding var isSuggestionsCollapsed: Bool

    let onOpenChat: (PromptBubble) -> Void
    let onStartWriting: (PromptBubble) -> Void
    let onRefreshSuggestions: () -> Void


    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: board.icon ?? "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text(board.title)
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Add an item to this board.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar Cluster

    var sortPicker: some View {
        Menu {
            ForEach(BoardSortOption.allCases, id: \.self) { option in
                Button {
                    sortOptionBinding = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.grove(.secondary, size: .compact))
        .help("Sort items (\(sortOption.rawValue))")
    }

    var viewModeButton: some View {
        Button {
            viewMode = viewMode == .grid ? .list : .grid
        } label: {
            Label(viewMode == .grid ? "List" : "Grid", systemImage: viewMode.iconName)
        }
        .buttonStyle(.grove(.secondary, size: .compact))
        .help(viewMode == .grid ? "Switch to list view" : "Switch to grid view")
    }

    var copyMarkdownButton: some View {
        Button {
            let markdown = BoardExportService.markdownForBoard(
                board,
                items: displayedItems,
                options: BoardExportOptions()
            )
            BoardExportService.copyToClipboard(markdown)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.on.doc")
        }
        .buttonStyle(.grove(.secondary, size: .compact))
        .disabled(displayedItems.isEmpty)
        .help("Copy this board's items as Markdown")
    }

    @ViewBuilder
    var toolbarCluster: some View {
        HStack(spacing: Spacing.sm) {
            sortPicker
            viewModeButton
            copyMarkdownButton
        }
    }

    // MARK: - Suggestions Bar

    @ViewBuilder
    var suggestionsBar: some View {
        if !boardDiscussionSuggestions.isEmpty {
            BoardSuggestionsView(
                suggestions: boardDiscussionSuggestions,
                isSuggestionsCollapsed: $isSuggestionsCollapsed,
                onOpenChat: onOpenChat,
                onStartWriting: onStartWriting,
                onRefresh: onRefreshSuggestions
            )
        }
    }
}
