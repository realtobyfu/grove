import Foundation
import SQLiteData

extension AppDatabase {
    /// The app's database, for defaulting a service's `database` parameter. Tests
    /// pass their own.
    static var current: any DatabaseWriter {
        @Dependency(\.defaultDatabase) var database
        return database
    }
}

extension DatabaseWriter {
    /// For a write whose failure has nowhere to go but the log, which is most of
    /// the UI. Reach for `write` instead when the caller can act on the error.
    ///
    /// Inside the closure, use `db` for every read: calling the database itself
    /// from a transaction is a crash.
    @discardableResult
    func attempt<T>(_ updates: (Database) throws -> T) -> T? {
        do {
            return try write(updates)
        } catch {
            databaseLog.error("Write failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// As `attempt`, for reads.
    func attemptRead<T>(_ value: (Database) throws -> T) -> T? {
        do {
            return try read(value)
        } catch {
            databaseLog.error("Read failed: \(error, privacy: .public)")
            return nil
        }
    }
}

extension PrimaryKeyedTable where PrimaryKey == UUID, QueryOutput == Self, TableColumns.PrimaryColumn: WritableTableColumnExpression {
    /// Changes the row with this ID, and returns it, or `nil` if it's gone.
    ///
    /// Prefer this to saving a copy you already hold. It reads the row inside the
    /// transaction, so a field someone else changed since you read yours survives.
    @discardableResult
    static func modify(
        _ id: UUID,
        in db: Database,
        _ body: (inout Self) throws -> Void
    ) throws -> Self? {
        guard var row = try find(id).fetchOne(db) else { return nil }
        try body(&row)
        try update(row).execute(db)
        return row
    }
}

extension Item {
    /// Puts the item on `boardID`, or on no board. An item is on at most one.
    static func setBoard(_ boardID: Board.ID?, forItem id: Item.ID, in db: Database) throws {
        try modify(id, in: db) {
            $0.boardID = boardID
            $0.updatedAt = .now
        }
    }

    static func addTag(_ tagID: Tag.ID, toItem id: Item.ID, in db: Database) throws {
        try ItemTag.insert { ItemTag(itemID: id, tagID: tagID) } onConflictDoUpdate: { _ in }.execute(db)
    }

    static func removeTag(_ tagID: Tag.ID, fromItem id: Item.ID, in db: Database) throws {
        try ItemTag.where { $0.itemID.eq(id) && $0.tagID.eq(tagID) }.delete().execute(db)
    }

    /// Stores a thumbnail, replacing any already there.
    static func setThumbnail(_ data: Data?, forItem id: Item.ID, in db: Database) throws {
        guard let data else {
            try ItemThumbnail.find(id).delete().execute(db)
            return
        }
        try ItemThumbnail.upsert { ItemThumbnail(itemID: id, imageData: data) }.execute(db)
    }
}

extension ReflectionBlock {
    /// The position after the last block on an item. Call it in the transaction
    /// that inserts: a graph the caller holds can be behind the database, and
    /// would hand out a position already taken.
    static func nextPosition(onItem itemID: Item.ID, in db: Database) throws -> Int {
        let last = try ReflectionBlock
            .where { $0.itemID.eq(itemID) }
            .order { $0.position.desc() }
            .fetchOne(db)
        return (last?.position ?? -1) + 1
    }
}

extension Board {
    static func addSmartRuleTag(_ tagID: Tag.ID, toBoard id: Board.ID, in db: Database) throws {
        try BoardSmartRuleTag.insert { BoardSmartRuleTag(boardID: id, tagID: tagID) } onConflictDoUpdate: { _ in }.execute(db)
    }

    static func removeAllSmartRuleTags(fromBoard id: Board.ID, in db: Database) throws {
        try BoardSmartRuleTag.where { $0.boardID.eq(id) }.delete().execute(db)
    }
}
