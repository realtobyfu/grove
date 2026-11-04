import SQLiteData
import SwiftUI

extension View {
    /// Keeps a held item in step with the library. Items are values, so state
    /// holding one would otherwise keep showing what it was when it was selected.
    ///
    /// An item that has been deleted clears the state. The library can be a moment
    /// behind a write, so one missing from it is only gone if the database agrees:
    /// otherwise state set from an item created just now would clear itself.
    func keepingCurrent(_ item: Binding<ItemGraph?>, in library: Library) -> some View {
        onChange(of: library) { _, library in
            guard let id = item.wrappedValue?.id else { return }
            if let current = library.item(id) {
                item.wrappedValue = current
            } else if !Item.exists(id) {
                item.wrappedValue = nil
            }
        }
    }

    /// As above, for a held board.
    func keepingCurrent(_ board: Binding<BoardGraph?>, in library: Library) -> some View {
        onChange(of: library) { _, library in
            guard let id = board.wrappedValue?.id else { return }
            if let current = library.board(id) {
                board.wrappedValue = current
            } else if !Board.exists(id) {
                board.wrappedValue = nil
            }
        }
    }

    /// As above, for a held tag.
    func keepingCurrent(_ tag: Binding<TagGraph?>, in library: Library) -> some View {
        onChange(of: library) { _, library in
            guard let id = tag.wrappedValue?.id else { return }
            if let current = library.tag(id) {
                tag.wrappedValue = current
            } else if !Tag.exists(id) {
                tag.wrappedValue = nil
            }
        }
    }
}

private extension PrimaryKeyedTable where PrimaryKey == UUID, QueryOutput == Self {
    /// A failed read counts as still there: clearing state is the costly mistake.
    static func exists(_ id: UUID) -> Bool {
        AppDatabase.current.attemptRead { try find(id).fetchOne($0) != nil } ?? true
    }
}
