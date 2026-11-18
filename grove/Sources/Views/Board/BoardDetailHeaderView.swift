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
        GroveEmptyState(
            title: "Nothing on this board yet.",
            detail: "Paste a link or type a note in the bar above."
        )
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        // A trail is always the user's own order, so there is nothing to sort
        // there. The choice is kept for the grid and the list.
        .disabled(viewMode == .trail)
        .help(viewMode == .trail
            ? "Trail follows your own order"
            : "Sort items (\(sortOption.rawValue))")
    }

    /// Trail, Grid, List. The current view is the ink-filled button.
    var viewModeSwitcher: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(BoardViewMode.allCases, id: \.self) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Text(mode.title)
                }
                .buttonStyle(.grove(viewMode == mode ? .primary : .secondary, size: .compact))
                .help("Show this board as a \(mode.title.lowercased())")
                .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
            }
        }
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
            viewModeSwitcher
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
