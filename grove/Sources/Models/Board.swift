import Foundation
import SQLiteData

enum SmartRuleLogic: String, Codable, CaseIterable, QueryBindable {
    case and
    case or

    var displayName: String {
        switch self {
        case .and: return "AND"
        case .or: return "OR"
        }
    }

    var description: String {
        switch self {
        case .and: return "Items must have ALL selected tags"
        case .or: return "Items must have ANY selected tag"
        }
    }
}

/// The sharing root. Keep this table free of foreign keys: SQLiteData can
/// only share a record that has none.
@Table("boards")
struct Board: Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String = ""
    var boardDescription: String?
    var icon: String?
    var color: String?
    var createdAt: Date = .now
    var sortOrder: Int = 0
    var isSmart: Bool = false
    var smartRuleLogic: SmartRuleLogic = .or
    /// Per-board nudge frequency in hours. 0 = use global default, -1 = disabled for this board.
    var nudgeFrequencyHours: Int = 0
    /// Manual item order. Empty means none has been set.
    @Column(as: [UUID].JSONRepresentation.self)
    var itemOrder: [UUID] = []
}

extension Board {
    init(title: String, icon: String? = nil, color: String? = nil) {
        self.init(id: UUID(), title: title, icon: icon, color: color)
    }
}
