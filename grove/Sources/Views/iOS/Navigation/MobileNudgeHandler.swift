import SwiftUI
import SwiftData

/// Handles push nudge notification responses on iOS.
/// Listens for groveOpenNudgeNotification and groveDismissNudgeNotification,
/// then updates the Nudge model and routes via DeepLinkRouter.
struct MobileNudgeHandler: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenNudgeNotification)) { notification in
                guard let nudgeID = notification.object as? UUID else { return }
                handleOpen(nudgeID: nudgeID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveDismissNudgeNotification)) { notification in
                guard let nudgeID = notification.object as? UUID else { return }
                handleDismiss(nudgeID: nudgeID)
            }
    }

    private func handleOpen(nudgeID: UUID) {
        guard let nudge = fetchNudge(id: nudgeID) else { return }
        nudge.status = .actedOn
        try? modelContext.save()

        // Route to the nudge's target item via deep link
        if let targetItem = nudge.targetItem {
            deepLinkRouter.handle(URL(string: "grove://item/\(targetItem.id.uuidString)")!)
        }
    }

    private func handleDismiss(nudgeID: UUID) {
        guard let nudge = fetchNudge(id: nudgeID) else { return }
        nudge.status = .dismissed
        try? modelContext.save()
    }

    private func fetchNudge(id: UUID) -> Nudge? {
        let descriptor = FetchDescriptor<Nudge>()
        let allNudges = (try? modelContext.fetch(descriptor)) ?? []
        return allNudges.first { $0.id == id }
    }
}

extension View {
    func mobileNudgeHandler() -> some View {
        modifier(MobileNudgeHandler())
    }
}
