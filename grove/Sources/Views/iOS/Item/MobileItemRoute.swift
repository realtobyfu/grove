import SQLiteData
import SwiftUI

struct MobileItemRoute: Hashable, Identifiable, Sendable {
    let id: UUID
}

struct MobileItemRouteDestinationView: View {
    @Fetch private var item: ItemGraph?

    init(route: MobileItemRoute) {
        _item = Fetch(wrappedValue: nil, ItemGraph.Request(id: route.id))
    }

    var body: some View {
        Group {
            if let item {
                MobileItemReaderView(item: item)
            } else {
                ContentUnavailableView("Item not found", systemImage: "doc.text")
            }
        }
    }
}
