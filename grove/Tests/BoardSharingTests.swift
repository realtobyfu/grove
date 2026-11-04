import CloudKit
import Foundation
import SQLiteData
import Testing
@testable import grove

/// Nothing shares yet, but the schema has to allow it. In a test, `SyncEngine` runs
/// against SQLiteData's mock CloudKit, so this exercises the real sharing path
/// without touching iCloud.
struct BoardSharingTests {
    @Test func aBoardSharesWithItsItemsButNotItsChats() async throws {
        let path = NSTemporaryDirectory() + "BoardSharingTests-\(UUID().uuidString).sqlite"
        var configuration = AppDatabase.configuration()
        configuration.prepareDatabase {
            try $0.attachMetadatabase(containerIdentifier: "iCloud.dev.tuist.grove")
        }
        let database = try DatabasePool(path: path, configuration: configuration)
        try AppDatabase.migrator.migrate(database)
        let engine = try AppDatabase.makeSyncEngine(for: database, startImmediately: true)

        let boardID = UUID()
        let itemID = UUID()
        let tagID = UUID()
        let conversationID = UUID()
        try await database.write { db in
            try Board.insert { Board(id: boardID, title: "Shared") }.execute(db)
            try Item.insert { Item(id: itemID, title: "On the board", boardID: boardID) }.execute(db)
            try Tag.insert { Tag(id: tagID, name: "tag") }.execute(db)
            try ItemTag.insert { ItemTag(itemID: itemID, tagID: tagID) }.execute(db)
            try ReflectionBlock.insert { ReflectionBlock(id: UUID(), itemID: itemID, content: "Thought") }.execute(db)
            try ItemThumbnail.insert { ItemThumbnail(itemID: itemID, imageData: Data([1])) }.execute(db)
            try Conversation.insert { Conversation(id: conversationID, title: "Private", boardID: boardID) }.execute(db)
            try ChatMessage.insert { ChatMessage(id: UUID(), conversationID: conversationID, content: "Secret") }.execute(db)
        }
        try await engine.sendChanges()

        let board = try #require(try await database.read { try Board.find(boardID).fetchOne($0) })
        _ = try await engine.share(record: board) { _ in }

        let metadata = try await database.read { try SyncMetadata.all.fetchAll($0) }
        func hasCloudKitParent(_ table: String) throws -> Bool {
            let row = try #require(metadata.first { $0.recordType == table }, "\(table) was not synced")
            let record = try #require(row.lastKnownServerRecord, "\(table) has no server record")
            return record.parent != nil
        }

        // A CKShare carries a root's descendants through `parent`, so these go with it.
        #expect(try hasCloudKitParent("items"))
        #expect(try hasCloudKitParent("reflectionBlocks"))
        #expect(try hasCloudKitParent("itemThumbnails"))

        // These must not. `conversations` holds a foreign key to the board, so this
        // is the line that keeps someone's chats out of a board they share.
        #expect(try !hasCloudKitParent("conversations"))
        #expect(try !hasCloudKitParent("chatMessages"))
        #expect(try !hasCloudKitParent("itemTags"))
        #expect(try !hasCloudKitParent("tags"))
    }

    @Test func onlyABoardCanBeShared() async throws {
        let path = NSTemporaryDirectory() + "BoardSharingTests-\(UUID().uuidString).sqlite"
        let database = try DatabasePool(path: path, configuration: AppDatabase.configuration())
        try AppDatabase.migrator.migrate(database)
        let engine = try AppDatabase.makeSyncEngine(for: database, startImmediately: true)

        let item = Item(id: UUID(), title: "Not a root")
        try await database.write { db in
            try Item.insert { item }.execute(db)
        }
        try await engine.sendChanges()

        await #expect(throws: (any Error).self) {
            _ = try await engine.share(record: item) { _ in }
        }
    }
}
