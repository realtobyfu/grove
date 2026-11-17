import Foundation
import SwiftData

/// Turns boards that were smart boards into ordinary boards without emptying
/// them.
///
/// A smart board computed its items from tag rules and stored none, so once
/// smart boards were removed such a board showed nothing. This adds the items
/// its rule matched to its stored items, then clears `isSmart`. The rule
/// fields (`smartRuleTags`, `smartRuleLogic`) stay in place, inert.
///
/// Keyed on `isSmart`, so it is idempotent; it runs every launch because a
/// smart board can still sync in from a device on an older build. Adding an
/// item a board already holds is a no-op, so two synced devices running it
/// for the same board converge on the same items.
@MainActor
enum SmartBoardMigrationService {
    static func migrateBoards(context: ModelContext) {
        let boards: [Board] = context.fetchAll()
        let smartBoards = boards.filter(\.isSmart)
        guard !smartBoards.isEmpty else { return }
        let items: [Item] = context.fetchAll()
        for board in smartBoards {
            materialize(board, allItems: items)
        }
        try? context.save()
    }

    /// Migrates one board, for callers about to edit it. No-op for a board
    /// that is not smart. Does not save.
    static func migrate(_ board: Board, context: ModelContext) {
        guard board.isSmart else { return }
        materialize(board, allItems: context.fetchAll())
    }

    private static func materialize(_ board: Board, allItems: [Item]) {
        let present = Set(board.items.map(\.id))
        for item in matchingItems(for: board, from: allItems) where !present.contains(item.id) {
            board.items.append(item)
        }
        board.isSmart = false
    }

    /// The rule smart boards used (removed in d3f0712): with AND an item needs
    /// every rule tag, with OR any one. A board with no rule tags matched
    /// nothing.
    static func matchingItems(for board: Board, from allItems: [Item]) -> [Item] {
        let ruleTagIDs = Set(board.smartRuleTags.map(\.id))
        guard !ruleTagIDs.isEmpty else { return [] }
        return allItems.filter { item in
            let itemTagIDs = Set(item.tags.map(\.id))
            switch board.smartRuleLogic {
            case .and: return ruleTagIDs.isSubset(of: itemTagIDs)
            case .or: return !ruleTagIDs.isDisjoint(with: itemTagIDs)
            }
        }
    }
}
