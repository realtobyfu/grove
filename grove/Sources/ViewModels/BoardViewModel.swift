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

    /// `color` is a bare hex from `BoardColor`; `nil` leaves a new board in
    /// plain ink and an existing board of the same name as it was.
    func createBoard(title: String, icon: String?, color: String? = nil) {
        let cleanedTitle = BoardSuggestionEngine.cleanedBoardName(title)
        guard !cleanedTitle.isEmpty else { return }

        if let existingBoard = fetchBoard(withTitle: cleanedTitle) {
            if let icon, !icon.isEmpty {
                existingBoard.icon = icon
            }
            if let color {
                existingBoard.color = color
            }
            // A not-yet-migrated smart board keeps the items its rule matched.
            SmartBoardMigrationService.migrate(existingBoard, context: modelContext)
            try? modelContext.save()
            return
        }

        let maxSortOrder = fetchMaxSortOrder()
        let board = Board(title: cleanedTitle, icon: icon, color: color)
        board.sortOrder = maxSortOrder + 1
        modelContext.insert(board)
        try? modelContext.save()
    }

    /// `color` is the editor's choice and is stored as given: `nil` clears it.
    func updateBoard(_ board: Board, title: String, icon: String?, color: String?) {
        let cleanedTitle = BoardSuggestionEngine.cleanedBoardName(title)
        guard !cleanedTitle.isEmpty else { return }

        board.title = cleanedTitle
        board.icon = icon
        // An unchanged colour keeps its stored spelling, so saving an edit
        // doesn't rewrite (and re-sync) a value the user never touched.
        if BoardColor.normalized(board.color) != BoardColor.normalized(color) {
            board.color = color
        }
        // A not-yet-migrated smart board keeps the items its rule matched.
        SmartBoardMigrationService.migrate(board, context: modelContext)
        try? modelContext.save()
    }

    func deleteBoard(_ board: Board) {
        modelContext.delete(board)
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
