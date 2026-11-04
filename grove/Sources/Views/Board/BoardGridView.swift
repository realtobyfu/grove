#if os(macOS)
import AppKit
#endif
import SwiftUI

struct BoardGridView: View {
    private enum Layout {
        static let minCardWidth: CGFloat = 300
        static let maxCardWidth: CGFloat = 420
        static let maxGridWidth: CGFloat = 1450
    }

    let items: [ItemGraph]
    var sections: [WeekSection]?
    let canReorder: Bool
    @Binding var selectedItem: ItemGraph?
    @Binding var openedItem: ItemGraph?
    @Binding var draggingItemID: UUID?
    var onOpenItem: ((ItemGraph) -> Void)? = nil
    var itemContextMenu: (ItemGraph) -> AnyView
    var onReorder: (UUID, UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Layout.minCardWidth, maximum: Layout.maxCardWidth), spacing: Spacing.lg, alignment: .top)],
                spacing: Spacing.lg
            ) {
                if let sections {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                gridCard(item)
                            }
                        } header: {
                            WeekSectionHeaderView(title: section.title)
                        }
                    }
                } else {
                    ForEach(items) { item in
                        gridCard(item)
                    }
                }
            }
            .frame(maxWidth: Layout.maxGridWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
        }
    }

    private func gridCard(_ item: ItemGraph) -> some View {
        Button {
            openItem(item)
        } label: {
            ItemCardView(
                item: item,
                showTags: true,
                usesContainerReadAction: true
            )
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(canReorder && draggingItemID == item.id ? 0.4 : 1)
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

    private func openItem(_ item: ItemGraph) {
        selectedItem = item
        if let onOpenItem {
            onOpenItem(item)
        } else {
            openedItem = item
        }
    }
}
