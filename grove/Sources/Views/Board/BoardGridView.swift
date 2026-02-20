import AppKit
import SwiftUI
import SwiftData

struct BoardGridView: View {
    private enum Layout {
        static let minCardWidth: CGFloat = 300
        static let maxCardWidth: CGFloat = 420
        static let maxGridWidth: CGFloat = 1450
    }

    let items: [Item]
    let canReorder: Bool
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Binding var draggingItemID: UUID?
    var itemContextMenu: (Item) -> AnyView
    var onReorder: (UUID, UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Layout.minCardWidth, maximum: Layout.maxCardWidth), spacing: Spacing.lg, alignment: .top)],
                spacing: Spacing.lg
            ) {
                ForEach(items) { item in
                    gridCard(item)
                }
            }
            .frame(maxWidth: Layout.maxGridWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
        }
    }

    private func gridCard(_ item: Item) -> some View {
        ItemCardView(item: item, showTags: true, onReadInApp: {
            openedItem = item
            selectedItem = item
        })
        .clipped()
        .opacity(canReorder && draggingItemID == item.id ? 0.4 : 1)
        .onTapGesture(count: 2) {
            openedItem = item
            selectedItem = item
        }
        .onTapGesture(count: 1) {
            selectedItem = item
        }
        .selectedItemStyle(selectedItem?.id == item.id)
        .contextMenu { itemContextMenu(item) }
        .onDrag {
            guard canReorder else { return NSItemProvider() }
            draggingItemID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: BoardGridDropDelegate(
            targetItemID: item.id,
            draggingItemID: $draggingItemID,
            isEnabled: canReorder,
            onReorder: onReorder
        ))
    }
}
