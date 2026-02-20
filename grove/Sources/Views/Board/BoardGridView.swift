import AppKit
import SwiftUI
import SwiftData

struct BoardGridView: View {
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
                columns: [GridItem(.adaptive(minimum: 220, maximum: 420), spacing: Spacing.lg)],
                spacing: Spacing.lg
            ) {
                ForEach(items) { item in
                    gridCard(item)
                }
            }
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
