import SwiftUI
import SwiftData

struct MobileItemRoute: Hashable, Identifiable, Sendable {
    let id: UUID
}

struct MobileItemRouteDestinationView: View {
    let route: MobileItemRoute

    @Environment(\.modelContext) private var modelContext
    @State private var item: Item?

    var body: some View {
        Group {
            if let item {
                MobileItemReaderView(item: item)
            } else {
                GroveEmptyState(
                    title: "This item is gone.",
                    detail: "It may have been deleted on another device."
                )
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.bgPrimary)
            }
        }
        // Reading gets the whole screen: no tab bar under the page.
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .task(id: route.id) {
            let itemID = route.id
            let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            self.item = try? modelContext.fetch(descriptor).first
        }
    }
}
