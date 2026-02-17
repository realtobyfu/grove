import Foundation
import SwiftData

enum SmartRuleLogic: String, Codable, CaseIterable {
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

@Model
final class Board {
    var id: UUID
    var title: String
    var boardDescription: String?
    var icon: String?
    var color: String?
    var createdAt: Date
    var sortOrder: Int
    var isSmart: Bool
    var smartRuleLogic: SmartRuleLogic
    /// Per-board nudge frequency in hours. 0 = use global default, -1 = disabled for this board.
    var nudgeFrequencyHours: Int

    var items: [Item]
    var smartRuleTags: [Tag]

    init(title: String, icon: String? = nil, color: String? = nil) {
        self.id = UUID()
        self.title = title
        self.boardDescription = nil
        self.icon = icon
        self.color = color
        self.createdAt = .now
        self.sortOrder = 0
        self.isSmart = false
        self.smartRuleLogic = .or
        self.nudgeFrequencyHours = 0
        self.items = []
        self.smartRuleTags = []
    }
}
