import SQLiteData
import SwiftUI

/// iPhone/iPad inbox triage view with swipe actions.
/// Trailing swipe (right): Keep (.active) and Move to Board.
/// Leading swipe (left): Drop (.dismissed).
struct MobileInboxView: View {
    @Dependency(\.defaultDatabase) private var database
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @Fetch(Library.Request()) private var library = Library()
    @FetchAll(Board.order(by: \.sortOrder)) private var boards

    @State private var showBoardPicker = false
    @State private var itemToAssign: ItemGraph?

    var onOpenItem: ((ItemGraph) -> Void)? = nil
    var selectedItem: Binding<ItemGraph?>? = nil
    var openedItem: Binding<ItemGraph?>? = nil

    /// Newest first.
    private var inboxItems: [ItemGraph] {
        library.items
            .filter { $0.status == .inbox && !$0.isFeedSuggestion }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if inboxItems.isEmpty {
                emptyState
            } else {
                inboxList
            }
        }
        .navigationTitle("Inbox")
        .navigationDestination(for: MobileItemRoute.self) { route in
            MobileItemRouteDestinationView(route: route)
        }
        .keepingCurrent($itemToAssign, in: library)
        .sheet(isPresented: $showBoardPicker) {
            boardPickerSheet
        }
    }

    // MARK: - Inbox list

    private var inboxList: some View {
        List {
            ForEach(inboxItems) { item in
                openItemRow(item: item) {
                    MobileInboxCard(
                        item: item,
                        onConfirmTag: { tag in confirmTag(tag) },
                        onDismissTag: { tag in dismissTag(tag, from: item) }
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        keepItem(item)
                    } label: {
                        Label("Keep", systemImage: "checkmark.circle")
                    }
                    .tint(Color.textPrimary)

                    Button {
                        itemToAssign = item
                        showBoardPicker = true
                    } label: {
                        Label("Board", systemImage: "folder")
                    }
                    .tint(Color.textSecondary)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        dismissItem(item)
                    } label: {
                        Label("Drop", systemImage: "xmark")
                    }
                }
            }
        }
        .listStyle(.plain)
        // A triaged row leaves when `library` next arrives, after any `withAnimation`
        // around the write has ended, so the animation lives here.
        .animation(.default, value: inboxItems.map(\.id))
    }

    // MARK: - Empty state (P3.4)

    private var emptyState: some View {
        ContentUnavailableView {
            Label("All Caught Up", systemImage: "checkmark.circle")
        } description: {
            Text("Items you capture will appear here.")
        }
    }

    // MARK: - Board picker sheet

    @ViewBuilder
    private var boardPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(boards) { board in
                    Button {
                        if let item = itemToAssign {
                            assignToBoard(item, board: board)
                        }
                        showBoardPicker = false
                        itemToAssign = nil
                    } label: {
                        Label(board.title, systemImage: board.icon ?? "folder")
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .navigationTitle("Move to Board")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showBoardPicker = false
                        itemToAssign = nil
                    }
                }
            }
        }
    }

    // MARK: - Triage actions (P3.5)

    private func keepItem(_ item: ItemGraph) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        database.attempt { db in
            try Item.modify(item.id, in: db) {
                $0.status = .active
                $0.updatedAt = .now
            }
        }
    }

    private func dismissItem(_ item: ItemGraph) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        #endif
        database.attempt { db in
            try Item.modify(item.id, in: db) {
                $0.status = .dismissed
                $0.updatedAt = .now
            }
        }
    }

    private func assignToBoard(_ item: ItemGraph, board: Board) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        let viewModel = ItemViewModel()
        viewModel.assignToBoard(item.id, board: board)
    }

    private func confirmTag(_ tag: Tag) {
        database.attempt { db in
            try Tag.modify(tag.id, in: db) { $0.isAutoGenerated = false }
        }
    }

    private func dismissTag(_ tag: Tag, from item: ItemGraph) {
        database.attempt { db in
            try Item.removeTag(tag.id, fromItem: item.id, in: db)
            try Item.modify(item.id, in: db) { $0.updatedAt = .now }
        }
    }

    @ViewBuilder
    private func openItemRow<Content: View>(item: ItemGraph, @ViewBuilder content: () -> Content) -> some View {
        if let onOpenItem {
            Button {
                onOpenItem(item)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else if let selectedItem, let openedItem {
            Button {
                selectedItem.wrappedValue = item
                openedItem.wrappedValue = item
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else if let readerCoordinator {
            Button {
                readerCoordinator.selectedItem = item
                readerCoordinator.openedItem = item
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: MobileItemRoute(id: item.id)) {
                content()
            }
            .buttonStyle(.plain)
        }
    }
}
