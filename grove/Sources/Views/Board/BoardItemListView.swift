#if os(macOS)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

/// Extracted from BoardDetailView — item list/grid display with sorting, reorder, context menus, and video drop.
struct BoardItemListView: View {
    let board: Board
    let sortedFilteredItems: [Item]
    let weekSections: [WeekSection]?
    let canReorder: Bool
    let viewMode: BoardViewMode

    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Binding var draggingItemID: UUID?
    @Binding var itemToDelete: Item?

    let onMoveGrid: (UUID, UUID) -> Void
    let onMoveList: (IndexSet, Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch viewMode {
        case .grid:
            BoardGridView(
                items: sortedFilteredItems,
                sections: weekSections,
                canReorder: canReorder,
                selectedItem: $selectedItem,
                openedItem: $openedItem,
                draggingItemID: $draggingItemID,
                itemContextMenu: { item in AnyView(itemContextMenu(for: item)) },
                onReorder: onMoveGrid
            )
        case .list:
            BoardListView(
                items: sortedFilteredItems,
                sections: weekSections,
                canReorder: canReorder,
                selectedItem: $selectedItem,
                openedItem: $openedItem,
                itemContextMenu: { item in AnyView(itemContextMenu(for: item)) },
                onMove: onMoveList
            )
        }
    }

    // MARK: - Item Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: Item) -> some View {
        Button {
            openedItem = item
            selectedItem = item
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        if let urlString = item.sourceURL, let url = URL(string: urlString),
           item.metadata["videoLocalFile"] != "true" {
            Button {
                openedItem = item
                selectedItem = item
            } label: {
                Label("Read in App", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                openURL(url)
                #endif
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }

        Divider()

        if !board.isSmart {
            Button {
                let viewModel = ItemViewModel(modelContext: modelContext)
                viewModel.removeFromBoard(item, board: board)
            } label: {
                Label("Remove from Board", systemImage: "folder.badge.minus")
            }
        }

        Button(role: .destructive) {
            itemToDelete = item
        } label: {
            Label("Delete Item", systemImage: "trash")
        }
    }
}

// MARK: - Video Drop Handling

extension BoardItemListView {
    func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                let path = url.path
                guard CaptureService.isSupportedVideoFile(path) else { return }
                Task { @MainActor in
                    let captureService = CaptureService(modelContext: modelContext)
                    let item = captureService.createVideoItem(filePath: path, board: board.isSmart ? nil : board)
                    selectedItem = item
                }
            }
            handled = true
        }
        return handled
    }
}
