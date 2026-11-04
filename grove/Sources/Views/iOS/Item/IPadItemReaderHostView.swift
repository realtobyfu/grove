import SQLiteData
import SwiftUI

/// iPad detail host that uses the shared mac-style reader workflow:
/// overview + reflections first, then in-app article web view when the user opts in.
struct IPadItemReaderHostView: View {
    @Fetch private var item: ItemGraph?
    @State private var isWebViewActive = false

    init(itemID: Item.ID) {
        _item = Fetch(wrappedValue: nil, ItemGraph.Request(id: itemID))
    }

    var body: some View {
        if let item {
            ItemReaderView(
                item: item,
                isWebViewActive: $isWebViewActive,
                alwaysShowReflectionPanel: true
            )
            .navigationTitle(item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView("Item not found", systemImage: "doc.text")
        }
    }
}
