import Foundation
import SQLiteData
import SwiftUI

@MainActor
@Observable
final class BoardViewModel {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
    }

    func createBoard(title: String, icon: String?, color: String?, nudgeFrequencyHours: Int = 0) {
        let cleanedTitle = BoardSuggestionEngine.cleanedBoardName(title)
        guard !cleanedTitle.isEmpty else { return }

        database.attempt { db in
            if let existingBoard = try fetchBoard(withTitle: cleanedTitle, in: db) {
                try Board.modify(existingBoard.id, in: db) { board in
                    if let icon, !icon.isEmpty {
                        board.icon = icon
                    }
                    if let color, !color.isEmpty {
                        board.color = color
                    }
                    board.isSmart = false
                    board.nudgeFrequencyHours = nudgeFrequencyHours
                }
                try Board.removeAllSmartRuleTags(fromBoard: existingBoard.id, in: db)
                return
            }

            var board = Board(title: cleanedTitle, icon: icon, color: color)
            board.sortOrder = try fetchMaxSortOrder(in: db) + 1
            board.nudgeFrequencyHours = nudgeFrequencyHours
            let row = board
            try Board.insert { row }.execute(db)
        }
    }

    func createSmartBoard(title: String, icon: String?, color: String?, ruleTags: [Tag], logic: SmartRuleLogic, nudgeFrequencyHours: Int = 0) {
        _ = ruleTags
        _ = logic
        // Smart board creation is deprecated; treat as standard board creation.
        createBoard(title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFrequencyHours)
    }

    func updateBoard(_ boardID: Board.ID, title: String, icon: String?, color: String?, nudgeFrequencyHours: Int = 0) {
        let cleanedTitle = BoardSuggestionEngine.cleanedBoardName(title)
        guard !cleanedTitle.isEmpty else { return }

        database.attempt { db in
            try Board.modify(boardID, in: db) { board in
                board.title = cleanedTitle
                board.icon = icon
                board.color = color
                board.isSmart = false
                board.nudgeFrequencyHours = nudgeFrequencyHours
            }
            try Board.removeAllSmartRuleTags(fromBoard: boardID, in: db)
        }
    }

    func updateSmartBoard(_ boardID: Board.ID, title: String, icon: String?, color: String?, ruleTags: [Tag], logic: SmartRuleLogic, nudgeFrequencyHours: Int = 0) {
        _ = ruleTags
        _ = logic
        // Smart board editing is deprecated; treat as standard board update.
        updateBoard(boardID, title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFrequencyHours)
    }

    func deleteBoard(_ boardID: Board.ID) {
        database.attempt { db in
            try Board.find(boardID).delete().execute(db)
        }
    }

    func reorderBoards(_ boardIDs: [Board.ID]) {
        database.attempt { db in
            for (index, boardID) in boardIDs.enumerated() {
                try Board.modify(boardID, in: db) { $0.sortOrder = index }
            }
        }
    }

    func moveBoard(from source: IndexSet, to destination: Int, in boardIDs: [Board.ID]) {
        var ordered = boardIDs
        ordered.move(fromOffsets: source, toOffset: destination)
        reorderBoards(ordered)
    }

    /// Returns items matching the smart board's tag rules
    nonisolated static func smartBoardItems(for board: BoardGraph, from allItems: [ItemGraph]) -> [ItemGraph] {
        guard board.isSmart, !board.smartRuleTags.isEmpty else { return [] }

        let ruleTagIDs = Set(board.smartRuleTags.map(\.id))

        return allItems.filter { item in
            let itemTagIDs = Set(item.tags.map(\.id))
            switch board.smartRuleLogic {
            case .and:
                return ruleTagIDs.isSubset(of: itemTagIDs)
            case .or:
                return !ruleTagIDs.isDisjoint(with: itemTagIDs)
            }
        }
    }

    private func fetchMaxSortOrder(in db: Database) throws -> Int {
        try Board.order { $0.sortOrder.desc() }.fetchOne(db)?.sortOrder ?? -1
    }

    private func fetchBoard(withTitle title: String, in db: Database) throws -> Board? {
        try Board.all.fetchAll(db).first { board in
            board.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
    }
}
