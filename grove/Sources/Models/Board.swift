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
    var id: UUID = UUID()
    var title: String = ""
    var boardDescription: String?
    var icon: String?
    var color: String?
    var createdAt: Date = Date.now
    var sortOrder: Int = 0
    var isSmart: Bool = false
    var smartRuleLogic: SmartRuleLogic = SmartRuleLogic.or
    /// Per-board nudge frequency in hours. 0 = use global default, -1 = disabled for this board.
    var nudgeFrequencyHours: Int = 0
    /// JSON-encoded [UUID] array for manual item ordering. Authoritative source for .manual sort order.
    var itemOrderData: Data?

    // MARK: - Relationships
    //
    // CloudKit requires every relationship to be optional and to declare an
    // inverse, or `NSPersistentCloudKitContainer` refuses to load the model and
    // sync silently falls back to local-only. So the stored properties are
    // optional arrays, and each is fronted by a non-optional computed accessor
    // so call sites can keep treating them as plain `[T]`.
    //
    // `originalName` maps each renamed property back onto the pre-existing store
    // so local data survives the migration.

    @Relationship(originalName: "items") var itemsStorage: [Item]? = []
    @Relationship(originalName: "smartRuleTags") var smartRuleTagsStorage: [Tag]? = []
    /// Inverse of `Conversation.board`. New in 2.0, so it has no `originalName`.
    @Relationship(inverse: \Conversation.board) var conversationsStorage: [Conversation]? = []

    var items: [Item] {
        get { itemsStorage ?? [] }
        set { itemsStorage = newValue }
    }

    var smartRuleTags: [Tag] {
        get { smartRuleTagsStorage ?? [] }
        set { smartRuleTagsStorage = newValue }
    }

    var conversations: [Conversation] {
        get { conversationsStorage ?? [] }
        set { conversationsStorage = newValue }
    }

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
        self.itemOrderData = nil
        self.itemsStorage = []
        self.smartRuleTagsStorage = []
        self.conversationsStorage = []
    }
}

extension Board {
    func manualOrder() -> [UUID] {
        guard let data = itemOrderData,
              let order = try? JSONDecoder().decode([UUID].self, from: data) else {
            return items.map(\.id)
        }
        let validIDs = Set(items.map(\.id))
        return order.filter { validIDs.contains($0) }
    }

    func setManualOrder(_ order: [UUID]) {
        itemOrderData = try? JSONEncoder().encode(order)
    }
}
