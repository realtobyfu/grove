import Foundation
import SwiftData

extension Legacy {
    /// Learning choices belong to the synced library. Notification delivery and
    /// transient window/session layout remain local to each device.
    @Model
    final class UserLearningPreferences {
        var id: UUID = UUID(uuidString: "2776BFF0-9131-4BA7-9F43-9809986417D1")!
        var focusBoardIDs: [UUID] = []
        var sessionMinutes: Int = 3
        var updatedAt: Date = Date.now

        init(focusBoardIDs: [UUID] = [], sessionMinutes: Int = 3) {
            self.focusBoardIDs = focusBoardIDs
            self.sessionMinutes = sessionMinutes
        }

        var sessionCardLimit: Int {
            switch sessionMinutes {
            case ...1: 2
            case 2...3: 5
            default: 8
            }
        }
    }
}

typealias UserLearningPreferences = Legacy.UserLearningPreferences

/// The stored entity is named `UserLearningPreferences` so it sorts after every 2.0 entity.
/// Read "Migration Limits" in SharedModelContainer.swift before adding a model.
typealias LearningPreferences = UserLearningPreferences
