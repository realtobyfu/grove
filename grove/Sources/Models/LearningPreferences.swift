import Foundation
import SQLiteData

/// Learning choices belong to the synced library. Notification delivery and
/// transient window/session layout remain local to each device.
@Table("learningPreferences")
struct LearningPreferences: Hashable, Identifiable, Sendable {
    let id: UUID
    @Column(as: [UUID].JSONRepresentation.self)
    var focusBoardIDs: [UUID] = []
    var sessionMinutes: Int = 3
    var updatedAt: Date = .now
}

extension LearningPreferences {
    /// The one row a library has. Two devices can each create it, so sync has to
    /// meet on the same ID.
    static let sharedID = UUID(uuidString: "2776BFF0-9131-4BA7-9F43-9809986417D1")!

    init(focusBoardIDs: [UUID] = [], sessionMinutes: Int = 3) {
        self.init(id: Self.sharedID, focusBoardIDs: focusBoardIDs, sessionMinutes: sessionMinutes)
    }

    var sessionCardLimit: Int {
        switch sessionMinutes {
        case ...1: 2
        case 2...3: 5
        default: 8
        }
    }
}
