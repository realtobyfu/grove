import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class BoardViewModel {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createBoard(title: String, icon: String?, color: String?, nudgeFrequencyHours: Int = 0) {
        let cleanedTitle = BoardSuggestionEngine.cleanedBoardName(title)
        guard !cleanedTitle.isEmpty else { return }

        if let existingBoard = fetchBoard(withTitle: cleanedTitle) {
            if let icon, !icon.isEmpty {
                existingBoard.icon = icon
            }
            if let color, !color.isEmpty {
                existingBoard.color = color
            }
            existingBoard.isSmart = false
            existingBoard.smartRuleTags.removeAll()
            existingBoard.nudgeFrequencyHours = nudgeFrequencyHours
            try? modelContext.save()
            return
        }

        let maxSortOrder = fetchMaxSortOrder()
        let board = Board(title: cleanedTitle, icon: icon, color: color)
        board.sortOrder = maxSortOrder + 1
        board.nudgeFrequencyHours = nudgeFrequencyHours
        modelContext.insert(board)
        try? modelContext.save()
    }

    func updateBoard(_ board: Board, title: String, icon: String?, color: String?, nudgeFrequencyHours: Int = 0) {
        let cleanedTitle = BoardSuggestionEngine.cleanedBoardName(title)
        guard !cleanedTitle.isEmpty else { return }

        board.title = cleanedTitle
        board.icon = icon
        board.color = color
        board.isSmart = false
        board.smartRuleTags.removeAll()
        board.nudgeFrequencyHours = nudgeFrequencyHours
        try? modelContext.save()
    }

    func deleteBoard(_ board: Board) {
        modelContext.delete(board)
        try? modelContext.save()
    }

    func reorderBoards(_ boards: [Board]) {
        for (index, board) in boards.enumerated() {
            board.sortOrder = index
        }
        try? modelContext.save()
    }

    func moveBoard(from source: IndexSet, to destination: Int, in boards: [Board]) {
        var ordered = boards
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, board) in ordered.enumerated() {
            board.sortOrder = index
        }
        try? modelContext.save()
    }

    /// Returns items matching the smart board's tag rules
    nonisolated static func smartBoardItems(for board: Board, from allItems: [Item]) -> [Item] {
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

    private func fetchMaxSortOrder() -> Int {
        let descriptor = FetchDescriptor<Board>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let boards = (try? modelContext.fetch(descriptor)) ?? []
        return boards.first?.sortOrder ?? -1
    }

    private func fetchBoard(withTitle title: String) -> Board? {
        let descriptor = FetchDescriptor<Board>()
        let allBoards = (try? modelContext.fetch(descriptor)) ?? []
        return allBoards.first { board in
            board.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
    }
}
