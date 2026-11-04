import Foundation
import SQLiteData
import Testing
@testable import grove

/// The read models, and the write rules that took over from SwiftData's live
/// objects. Rows are values, so every assertion here reads the database again.
struct LibraryTests {
    private struct Abandoned: Error {}

    // MARK: - Reading

    /// `Library` loads every table in one pass and `ItemGraph` queries one item's
    /// links, so nothing but this keeps the two telling the same story.
    @Test func libraryAndItemGraphAgreeOnOneItem() throws {
        let database = try AppDatabase.openInMemory()
        let board = Board(title: "Reading")
        var row = Item(title: "Essay", type: .article)
        row.boardID = board.id
        let item = row
        let cited = Item(title: "Cited", type: .note)
        let citing = Item(title: "Citing", type: .note)

        // Written out of order, so any order read back was put there by the read.
        let tags = ["zebra", "apple", "mango"].map { Tag(name: $0) }
        let reflections = [2, 0, 1].map {
            ReflectionBlock(itemID: item.id, blockType: .keyInsight, content: "Block \($0)", position: $0)
        }
        let outgoing = Connection(sourceItemID: item.id, targetItemID: cited.id, type: .buildsOn)
        let secondOutgoing = Connection(sourceItemID: item.id, targetItemID: citing.id, type: .related)
        let incoming = Connection(sourceItemID: citing.id, targetItemID: item.id, type: .inspiredBy)

        // Another item's links, which must not leak onto this one.
        let otherTag = Tag(name: "aardvark")
        let otherReflection = ReflectionBlock(itemID: cited.id, blockType: .connection, content: "Elsewhere", position: 0)
        let otherConnection = Connection(sourceItemID: cited.id, targetItemID: citing.id, type: .related)

        try database.write { db throws in
            try Board.insert { board }.execute(db)
            try Item.insert { [item, cited, citing] }.execute(db)
            try Tag.insert { tags + [otherTag] }.execute(db)
            for tag in tags {
                try Item.addTag(tag.id, toItem: item.id, in: db)
            }
            try Item.addTag(otherTag.id, toItem: cited.id, in: db)
            try ReflectionBlock.insert { reflections + [otherReflection] }.execute(db)
            try Connection.insert { [outgoing, secondOutgoing, incoming, otherConnection] }.execute(db)
        }

        let (library, fetched) = try database.read { db throws in
            (try Library.fetch(db), try ItemGraph.fetch(item.id, in: db))
        }
        let fromLibrary = try #require(library.item(item.id))
        let fromFetch = try #require(fetched)

        #expect(fromLibrary.item == fromFetch.item)

        #expect(fromLibrary.board?.id == board.id)
        #expect(fromFetch.board == fromLibrary.board)

        #expect(fromLibrary.tags.map(\.name) == ["apple", "mango", "zebra"])
        #expect(fromFetch.tags == fromLibrary.tags)

        #expect(fromLibrary.reflections.map(\.position) == [0, 1, 2])
        #expect(fromFetch.reflections == fromLibrary.reflections)

        #expect(Set(fromLibrary.outgoingConnections.map(\.id)) == [outgoing.id, secondOutgoing.id])
        #expect(Set(fromFetch.outgoingConnections) == Set(fromLibrary.outgoingConnections))
        #expect(fromLibrary.incomingConnections.map(\.id) == [incoming.id])
        #expect(fromFetch.incomingConnections == fromLibrary.incomingConnections)

        // Both ends arrive resolved, however the graph was read.
        for graph in [fromLibrary, fromFetch] {
            let edge = try #require(graph.outgoingConnections.first { $0.id == outgoing.id })
            #expect(edge.sourceItem?.id == item.id)
            #expect(edge.targetItem?.id == cited.id)
        }
    }

    // MARK: - Writing

    @Test func addingALinkThatExistsKeepsOneRow() throws {
        let database = try AppDatabase.openInMemory()
        let item = Item(title: "Tagged", type: .note)
        let tag = Tag(name: "once")
        let board = Board(title: "Smart")
        try database.write { db throws in
            try Item.insert { item }.execute(db)
            try Tag.insert { tag }.execute(db)
            try Board.insert { board }.execute(db)
            for _ in 0..<2 {
                try Item.addTag(tag.id, toItem: item.id, in: db)
                try Board.addSmartRuleTag(tag.id, toBoard: board.id, in: db)
            }
            #expect(try ItemTag.all.fetchCount(db) == 1)
            #expect(try BoardSmartRuleTag.all.fetchCount(db) == 1)
        }
    }

    @Test func modifyKeepsAFieldChangedSinceTheCallerReadItsCopy() throws {
        let database = try AppDatabase.openInMemory()
        let original = Item(title: "Draft", type: .note)
        try database.write { db throws in
            try Item.insert { original }.execute(db)
        }
        func saved() throws -> Item {
            try #require(try database.read { try Item.find(original.id).fetchOne($0) })
        }

        // A view reads the row, then something else writes to it.
        let held = try saved()
        try database.write { db throws in
            try Item.modify(held.id, in: db) { $0.content = "Written elsewhere" }
        }

        // The view's edit, made after its copy went stale.
        let returned = try database.write { db throws in
            try Item.modify(held.id, in: db) { $0.title = "Renamed" }
        }

        let merged = try saved()
        #expect(merged.title == "Renamed")
        #expect(merged.content == "Written elsewhere")
        #expect(returned == merged)
        #expect(held.content == nil)

        // Writing the stale copy back is the mistake `modify` exists to prevent.
        var stale = held
        stale.title = "Renamed again"
        try database.write { db throws in
            try Item.update(stale).execute(db)
        }
        #expect(try saved().content == nil)
    }

    @Test func modifyReturnsNilForARowThatIsGoneAndWritesNothing() throws {
        let database = try AppDatabase.openInMemory()

        let result = try database.write { db throws in
            try Item.modify(UUID(), in: db) { $0.title = "Never there" }
        }

        #expect(result == nil)
        #expect(try database.read { try Item.all.fetchCount($0) } == 0)
    }

    @Test func attemptReturnsTheClosuresValueWhenTheWriteSucceeds() throws {
        let database = try AppDatabase.openInMemory()
        let item = Item(title: "Kept", type: .note)

        let result = database.attempt { db -> Item.ID in
            try Item.insert { item }.execute(db)
            return item.id
        }

        #expect(result == item.id)
        #expect(try database.read { try Item.all.fetchCount($0) } == 1)
    }

    @Test func attemptReturnsNilAndRollsBackEveryWriteWhenTheClosureThrows() throws {
        let database = try AppDatabase.openInMemory()
        let existing = Item(title: "Before", type: .note)
        try database.write { db throws in
            try Item.insert { existing }.execute(db)
        }
        let added = Item(title: "Added", type: .note)
        let tag = Tag(name: "added")

        let result: Int? = database.attempt { db in
            try Item.insert { added }.execute(db)
            try Tag.insert { tag }.execute(db)
            try Item.addTag(tag.id, toItem: existing.id, in: db)
            try Item.modify(existing.id, in: db) { $0.title = "After" }
            throw Abandoned()
        }

        #expect(result == nil)
        try database.read { db throws in
            #expect(try Item.all.fetchAll(db).map(\.title) == ["Before"])
            #expect(try Tag.all.fetchCount(db) == 0)
            #expect(try ItemTag.all.fetchCount(db) == 0)
        }
    }

    @Test func attemptRollsBackWhenTheDatabaseRefusesAWrite() throws {
        let database = try AppDatabase.openInMemory()
        let first = Item(title: "Written first", type: .note)
        // A foreign key violation: this board doesn't exist.
        let orphan = Item(id: UUID(), title: "Orphan", boardID: UUID())

        let result = database.attempt { db -> Bool in
            try Item.insert { first }.execute(db)
            try Item.insert { orphan }.execute(db)
            return true
        }

        #expect(result == nil)
        #expect(try database.read { try Item.all.fetchCount($0) } == 0)
    }

    // MARK: - One Board Per Item

    @MainActor
    @Test func assignToBoardMovesAnItemOffItsPreviousBoard() throws {
        let database = try AppDatabase.openInMemory()
        let previous = Board(title: "Previous")
        let next = Board(title: "Next")
        var row = Item(title: "Moved", type: .note)
        row.boardID = previous.id
        let item = row
        try database.write { db throws in
            try Board.insert { [previous, next] }.execute(db)
            try Item.insert { item }.execute(db)
        }

        ItemViewModel(database: database).assignToBoard(item.id, board: next)

        let library = try database.read { try Library.fetch($0) }
        #expect(library.item(item.id)?.board?.id == next.id)
        #expect(library.board(next.id)?.items.map(\.id) == [item.id])
        #expect(library.board(previous.id)?.items.isEmpty == true)
    }

    @MainActor
    @Test func assignToASmartBoardLeavesTheBoardAlone() throws {
        let database = try AppDatabase.openInMemory()
        let home = Board(title: "Home")
        var smartRow = Board(title: "Smart")
        smartRow.isSmart = true
        let smart = smartRow
        var row = Item(title: "Filed", type: .note)
        row.boardID = home.id
        row.status = .inbox
        let filed = row
        let unfiled = Item(title: "Unfiled", type: .note)
        try database.write { db throws in
            try Board.insert { [home, smart] }.execute(db)
            try Item.insert { [filed, unfiled] }.execute(db)
        }
        let viewModel = ItemViewModel(database: database)

        viewModel.assignToBoard(filed.id, board: smart)
        viewModel.assignToBoard(unfiled.id, board: smart)

        let library = try database.read { try Library.fetch($0) }
        #expect(library.item(filed.id)?.boardID == home.id)
        #expect(library.item(unfiled.id)?.boardID == nil)
        #expect(library.board(smart.id)?.items.isEmpty == true)
        // The item still counts as triaged, as it did before a board was a column.
        #expect(library.item(filed.id)?.status == .active)
    }

    @MainActor
    @Test func mergingAnImportedItemAlreadyOnABoardKeepsThatBoardAndHoldsTheImportedOne() throws {
        let database = try AppDatabase.openInMemory()
        let home = Board(title: "Home")
        var row = Item(title: "Essay", type: .article)
        row.sourceURL = "https://example.com/essay"
        row.boardID = home.id
        let item = row
        try database.write { db throws in
            try Board.insert { home }.execute(db)
            try Item.insert { item }.execute(db)
        }

        let imported = try importMerging(item, into: database)

        #expect(imported.id != home.id)
        try database.read { db throws in
            #expect(try Item.find(item.id).fetchOne(db)?.boardID == home.id)
            #expect(try ExtraBoardLink.all.fetchAll(db) == [ExtraBoardLink(itemID: item.id, boardID: imported.id)])
        }
    }

    @MainActor
    @Test func mergingAnImportedItemOnNoBoardMovesItToTheImportedBoard() throws {
        let database = try AppDatabase.openInMemory()
        var row = Item(title: "Essay", type: .article)
        row.sourceURL = "https://example.com/essay"
        let item = row
        try database.write { db throws in
            try Item.insert { item }.execute(db)
        }

        let imported = try importMerging(item, into: database)

        try database.read { db throws in
            #expect(try Item.find(item.id).fetchOne(db)?.boardID == imported.id)
            #expect(try ExtraBoardLink.all.fetchCount(db) == 0)
        }
    }

    /// Imports a package holding one item with `item`'s URL, taking the preview's
    /// own decision, which has to be a merge.
    @MainActor
    private func importMerging(_ item: Item, into database: any DatabaseWriter) throws -> Board {
        let transfer = TransferItem(
            id: UUID(),
            title: "Essay, as exported",
            type: ItemType.article.rawValue,
            status: ItemStatus.active.rawValue,
            sourceURL: item.sourceURL,
            content: nil,
            tags: [],
            createdAt: .now,
            updatedAt: .now
        )
        let package = GrovePackage(
            manifest: GrovePackageManifest(
                version: 1,
                boardTitle: "Imported",
                boardIcon: nil,
                boardColor: nil,
                boardDescription: nil,
                exportDate: .now,
                itemCount: 1,
                groveVersion: "test"
            ),
            items: [transfer],
            reflections: [],
            connections: [],
            itemOrder: [transfer.id]
        )
        let library = try database.read { try Library.fetch($0) }
        let decisions = BoardPackageService.buildImportPreview(package: package, existingItems: library.items)
        #expect(decisions.map(\.decision) == [.mergeWithExisting])
        return try BoardPackageService.importPackage(package: package, decisions: decisions, database: database)
    }

    // MARK: - Tags

    @MainActor
    @Test func mergingTagsLeavesOneDeterministicLinkPerItemAndDeletesTheOldTag() throws {
        let database = try AppDatabase.openInMemory()
        let keep = Tag(name: "swift")
        let remove = Tag(name: "swift-lang")
        let child = Tag(id: UUID(), name: "swiftui", parentTagID: remove.id)
        let both = Item(title: "Both", type: .note)
        let removedOnly = Item(title: "Removed only", type: .note)
        let keptOnly = Item(title: "Kept only", type: .note)
        let smart = Board(title: "Smart")
        try database.write { db throws in
            try Tag.insert { [keep, remove, child] }.execute(db)
            try Item.insert { [both, removedOnly, keptOnly] }.execute(db)
            try Board.insert { smart }.execute(db)
            try Item.addTag(keep.id, toItem: both.id, in: db)
            try Item.addTag(remove.id, toItem: both.id, in: db)
            try Item.addTag(remove.id, toItem: removedOnly.id, in: db)
            try Item.addTag(keep.id, toItem: keptOnly.id, in: db)
            try Board.addSmartRuleTag(remove.id, toBoard: smart.id, in: db)
        }

        TagService(database: database).mergeTags(keep: keep.id, remove: remove.id)

        try database.read { db throws in
            // Comparing rows compares IDs too, and these derive theirs from the pair.
            let links = try ItemTag.all.fetchAll(db)
            #expect(links.count == 3)
            #expect(Set(links) == Set([both, removedOnly, keptOnly].map { ItemTag(itemID: $0.id, tagID: keep.id) }))

            #expect(try Tag.find(remove.id).fetchOne(db) == nil)
            #expect(try Tag.find(child.id).fetchOne(db)?.parentTagID == keep.id)
            #expect(try BoardSmartRuleTag.all.fetchAll(db) == [BoardSmartRuleTag(boardID: smart.id, tagID: keep.id)])
        }
    }

    // MARK: - Opening

    /// `openForApp` imports the SwiftData library only if the file is missing, so a
    /// file the extension created would strand that library for good.
    @Test func openingForTheExtensionNeverCreatesTheFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent(AppDatabase.directoryName, isDirectory: true)
        let url = directory.appendingPathComponent(AppDatabase.fileName)

        #expect(try AppDatabase.open(existingAt: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))

        // An empty folder is no library either.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(try AppDatabase.open(existingAt: url) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).isEmpty)
    }

    @Test func openingForTheExtensionFindsTheLibraryTheAppCreated() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder
            .appendingPathComponent(AppDatabase.directoryName, isDirectory: true)
            .appendingPathComponent(AppDatabase.fileName)
        let item = Item(title: "Saved by the app", type: .note)
        let created = try AppDatabase.open(at: url)
        try created.write { db throws in
            try Item.insert { item }.execute(db)
        }
        try created.close()

        let reopened = try #require(try AppDatabase.open(existingAt: url))
        defer { try? reopened.close() }

        #expect(try reopened.read { try Item.find(item.id).fetchOne($0) }?.title == "Saved by the app")
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Sync

    /// `extraBoardLinks` holds links the single-board model can't express, and
    /// they never leave this device. The table list in `makeSyncEngine` is private
    /// to the engine, so this watches what it does instead: a row in a synced
    /// table earns a metadata row, and `items` proves the engine is listening.
    @Test func extraBoardLinksStayOutOfTheSyncedTables() throws {
        let database = try AppDatabase.openInMemory()
        let engine = try AppDatabase.makeSyncEngine(for: database, startImmediately: false)
        let item = Item(title: "Synced", type: .note)

        try database.write { db throws in
            try Item.insert { item }.execute(db)
            try ExtraBoardLink.insert { ExtraBoardLink(itemID: item.id, boardID: UUID()) }.execute(db)
        }

        let recordTypes = try database.read { try SyncMetadata.all.fetchAll($0).map(\.recordType) }
        #expect(recordTypes.contains(Item.tableName))
        #expect(!recordTypes.contains(ExtraBoardLink.tableName))
        withExtendedLifetime(engine) {}
    }
}
