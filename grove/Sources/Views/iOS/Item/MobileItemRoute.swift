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
                ContentUnavailableView("Item not found", systemImage: "doc.text")
            }
        }
        .task(id: route.id) {
            let itemID = route.id
            let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            self.item = try? modelContext.fetch(descriptor).first
        }
    }
}
