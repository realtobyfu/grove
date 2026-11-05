import SwiftUI
import SwiftData

struct MobileItemRoute: Hashable, Identifiable, Sendable {
    let id: UUID
}

/// Counts item readers on screen, so the tab root can hide its capture button
/// behind them. A count, not a flag: opening a linked item stacks a second reader.
@MainActor
@Observable
final class ReaderPresence {
    private(set) var openCount = 0
    var isActive: Bool { openCount > 0 }

    func readerAppeared() { openCount += 1 }
    func readerDisappeared() { openCount = max(0, openCount - 1) }
}

struct MobileItemRouteDestinationView: View {
    let route: MobileItemRoute

    @Environment(\.modelContext) private var modelContext
    @Environment(ReaderPresence.self) private var readerPresence: ReaderPresence?
    @State private var item: Item?

    var body: some View {
        Group {
            if let item {
                MobileItemReaderView(item: item)
            } else {
                ContentUnavailableView("Item not found", systemImage: "doc.text")
            }
        }
        // Reading gets the whole screen: no tab bar under the page.
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .onAppear { readerPresence?.readerAppeared() }
        .onDisappear { readerPresence?.readerDisappeared() }
        .task(id: route.id) {
            let itemID = route.id
            let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            self.item = try? modelContext.fetch(descriptor).first
        }
    }
}
