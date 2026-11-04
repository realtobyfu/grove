import SQLiteData
import SwiftUI

/// Handles push nudge notification responses on iOS.
/// Listens for groveOpenNudgeNotification and groveDismissNudgeNotification,
/// then updates the Nudge model and routes via DeepLinkRouter.
struct MobileNudgeHandler: ViewModifier {
    @Dependency(\.defaultDatabase) private var database
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
        let nudge = database.attempt { db in
            try Nudge.modify(nudgeID, in: db) { $0.status = .actedOn }
        } ?? nil
        guard let nudge else { return }

        // Route to the nudge's target item via deep link
        if let targetItemID = nudge.targetItemID {
            deepLinkRouter.handle(URL(string: "grove://item/\(targetItemID.uuidString)")!)
        }
    }

    private func handleDismiss(nudgeID: UUID) {
        database.attempt { db in
            try Nudge.modify(nudgeID, in: db) { $0.status = .dismissed }
        }
    }
}

extension View {
    func mobileNudgeHandler() -> some View {
        modifier(MobileNudgeHandler())
    }
}
