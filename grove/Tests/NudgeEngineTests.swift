import Foundation
import SwiftData
import Testing
@testable import grove

/// Spaced resurfacing is retired: the engine only produces stale-inbox
/// nudges, and its sweep retires anything that can no longer reach the user.
struct NudgeEngineTests {

    @MainActor
    @Test func sweepRetiresResurfaceNudgesAndUnreachableStaleInbox() throws {
        let restore = Self.overrideDefaults(["nudge.notifications.enabled": false])
        defer { restore() }

        let context = try makeInMemoryModelContext()

        // No notification surface while notifications are off.
        let staleInbox = Nudge(type: .staleInbox, message: "8 items waiting")
        context.insert(staleInbox)

        // Nothing renders resurface nudges any more, targeted or not.
        let orphanResurface = Nudge(type: .resurface, message: "Revisit?")
        context.insert(orphanResurface)
        let target = Item(title: "Still here", type: .note)
        context.insert(target)
        let targetedResurface = Nudge(type: .resurface, message: "Revisit?", targetItem: target)
        context.insert(targetedResurface)
        let shownResurface = Nudge(type: .resurface, message: "Revisit?")
        shownResurface.status = .shown
        context.insert(shownResurface)

        // Control: already resolved, must keep its status.
        let actedOnResurface = Nudge(type: .resurface, message: "Revisit?")
        actedOnResurface.status = .actedOn
        context.insert(actedOnResurface)
        try context.save()

        let engine = NudgeEngine(modelContext: context)
        engine.sweepUnreachableNudges()

        #expect(staleInbox.status == .dismissed)
        #expect(orphanResurface.status == .dismissed)
        #expect(targetedResurface.status == .dismissed)
        #expect(shownResurface.status == .dismissed)
        #expect(actedOnResurface.status == .actedOn)
        // The target item is untouched; only the nudge is retired.
        #expect(targetedResurface.targetItem?.id == target.id)

        // Idempotent: a second run leaves the swept nudges exactly as they are.
        engine.sweepUnreachableNudges()
        #expect(staleInbox.status == .dismissed)
        #expect(targetedResurface.status == .dismissed)
        #expect(actedOnResurface.status == .actedOn)
    }

    @MainActor
    @Test func staleInboxNudgeIsGeneratedOnceThenSweptWithoutReplacement() throws {
        let restore = Self.overrideDefaults([
            "nudge.notifications.enabled": false,
            "nudge.staleInbox.enabled": true
        ])
        defer { restore() }

        let context = try makeInMemoryModelContext()
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: .now) ?? .now
        for index in 0..<AppConstants.Nudge.staleInboxMinCount {
            let item = Item(title: "Old capture \(index)", type: .note)
            item.createdAt = threeWeeksAgo
            context.insert(item)
        }
        try context.save()

        let engine = NudgeEngine(modelContext: context)
        engine.generateNudges()

        let generated: [Nudge] = context.fetchAll()
        #expect(generated.count == 1)
        #expect(generated.first?.type == .staleInbox)
        #expect(generated.first?.status == .pending)

        // Notifications are off, so the next run sweeps it, and the 30-day
        // cooldown keeps a replacement from being created straight away.
        engine.generateNudges()

        let afterSweep: [Nudge] = context.fetchAll()
        #expect(afterSweep.count == 1)
        #expect(afterSweep.first?.status == .dismissed)
    }

    // MARK: - Helpers

    @MainActor
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "NudgeEngineTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Sets standard-defaults keys for one test and returns a closure that
    /// puts back whatever was there before (including "absent").
    private static func overrideDefaults(_ values: [String: Bool]) -> () -> Void {
        let defaults = UserDefaults.standard
        let previous = values.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return {
            for (key, value) in previous {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }
}
