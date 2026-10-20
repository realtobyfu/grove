import Foundation

/// A small, non-sensitive snapshot. Widgets never load the knowledge store or call AI.
struct LearningWidgetSnapshot: Codable, Equatable, Sendable {
    var sessionMinutes: Int
    var hasCards: Bool
    var boardID: UUID?
    var updatedAt: Date

    static let empty = LearningWidgetSnapshot(
        sessionMinutes: 3, hasCards: false, boardID: nil, updatedAt: .distantPast
    )

    var reviewURL: URL {
        var components = URLComponents()
        components.scheme = "grove"
        components.host = "review"
        if let boardID {
            components.queryItems = [URLQueryItem(name: "board", value: boardID.uuidString)]
        }
        return components.url ?? URL(string: "grove://review")!
    }
}

enum LearningWidgetSnapshotStorage {
    private static let key = "grove.learning.widget.snapshot.v1"
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: "group.dev.tuist.grove")
    }

    static func read() -> LearningWidgetSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(LearningWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func write(_ snapshot: LearningWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
}
