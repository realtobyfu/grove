import Foundation
import OSLog
import SQLiteData

let databaseLog = Logger(subsystem: "dev.tuist.grove", category: "database")

/// Where the library lives and how it is opened.
///
/// The database is separate from the SwiftData store, which is never opened in
/// place and so stays byte-identical for the SwiftData branch of the app.
enum AppDatabase {
    static let directoryName = "GroveSQLite"
    static let fileName = "grove.sqlite"
    static let appGroupIdentifier = "group.dev.tuist.grove"

    /// The library's folder: inside the App Group on iOS, so that the Share
    /// Extension can reach it, and in Application Support otherwise.
    static func directoryURL() throws -> URL {
        #if os(iOS)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return container.appendingPathComponent(directoryName, isDirectory: true)
        }
        #endif
        return try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func databaseURL() throws -> URL {
        try directoryURL().appendingPathComponent(fileName)
    }

    /// Opens the file at `url`, creating and migrating it as needed.
    static func open(at url: URL) throws -> any DatabaseWriter {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration())
        try migrator.migrate(database)
        return database
    }

    /// An empty library in memory, for tests and the demo.
    static func openInMemory() throws -> any DatabaseWriter {
        let database = try DatabaseQueue(configuration: configuration())
        try migrator.migrate(database)
        return database
    }

    static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        // The app and the Share Extension can hold this file open together.
        configuration.busyMode = .timeout(5)
        #if os(iOS)
        // Without this, a suspended app holding a lock in the App Group is killed.
        configuration.observesSuspensionNotifications = true
        #endif
        return configuration
    }

    // MARK: - Migrations
    //
    // Once a migration ships it is frozen: a change needs a new migration, and
    // every device may be on a different version of this list. SQLiteData's
    // sync rules then apply (see its "Getting started with CloudKit" article):
    //
    // - Tables and columns are only ever added, never renamed or removed.
    // - An added column is nullable, or `NOT NULL ON CONFLICT REPLACE DEFAULT ...`
    //   so that a row from an older device, which lacks it, still inserts.
    // - Primary keys are single UUID columns, on every table, join tables too.
    // - No `UNIQUE` constraints, and `ON DELETE` is CASCADE, SET NULL or SET DEFAULT.
    // - No foreign key cycles, which rules out a table referencing itself.
    //
    // Never set `eraseDatabaseOnSchemaChange`, not even in DEBUG: this file holds
    // the owner's real library.

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("Create tables") { db in
            try db.execute(sql: createTables)
        }
        return migrator
    }

    private static let now = "(strftime('%Y-%m-%d %H:%M:%f', 'now'))"

    private static let createTables = """
        CREATE TABLE "boards" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "boardDescription" TEXT,
          "icon" TEXT,
          "color" TEXT,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "sortOrder" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "isSmart" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "smartRuleLogic" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'or',
          "nudgeFrequencyHours" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "itemOrder" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]'
        ) STRICT;

        CREATE TABLE "items" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "type" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'note',
          "status" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'inbox',
          "sourceURL" TEXT,
          "content" TEXT,
          "engagementScore" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "metadata" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '{}',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "readLaterUntil" TEXT,
          "lastResurfacedAt" TEXT,
          "resurfaceIntervalDays" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 7,
          "resurfaceCount" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "lastEngagedAt" TEXT,
          "isResurfacingPaused" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "boardID" TEXT REFERENCES "boards"("id") ON DELETE SET NULL
        ) STRICT;
        CREATE INDEX "index_items_on_boardID" ON "items"("boardID");

        CREATE TABLE "itemThumbnails" (
          "itemID" TEXT PRIMARY KEY NOT NULL REFERENCES "items"("id") ON DELETE CASCADE,
          "imageData" BLOB NOT NULL
        ) STRICT;

        CREATE TABLE "tags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "isAutoGenerated" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "confidence" REAL,
          "category" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'custom',
          "parentTagID" TEXT,
          "previousItemCount" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "trendCalculatedAt" TEXT
        ) STRICT;

        CREATE TABLE "itemTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "itemID" TEXT NOT NULL REFERENCES "items"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
        ) STRICT;
        CREATE INDEX "index_itemTags_on_itemID" ON "itemTags"("itemID");
        CREATE INDEX "index_itemTags_on_tagID" ON "itemTags"("tagID");

        CREATE TABLE "boardSmartRuleTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "boardID" TEXT NOT NULL REFERENCES "boards"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
        ) STRICT;
        CREATE INDEX "index_boardSmartRuleTags_on_boardID" ON "boardSmartRuleTags"("boardID");
        CREATE INDEX "index_boardSmartRuleTags_on_tagID" ON "boardSmartRuleTags"("tagID");

        CREATE TABLE "connections" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "sourceItemID" TEXT REFERENCES "items"("id") ON DELETE CASCADE,
          "targetItemID" TEXT REFERENCES "items"("id") ON DELETE CASCADE,
          "type" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'related',
          "note" TEXT,
          "isAutoGenerated" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now)
        ) STRICT;
        CREATE INDEX "index_connections_on_sourceItemID" ON "connections"("sourceItemID");
        CREATE INDEX "index_connections_on_targetItemID" ON "connections"("targetItemID");

        CREATE TABLE "annotations" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "itemID" TEXT REFERENCES "items"("id") ON DELETE CASCADE,
          "content" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "highlight" TEXT,
          "position" INTEGER,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now)
        ) STRICT;
        CREATE INDEX "index_annotations_on_itemID" ON "annotations"("itemID");

        CREATE TABLE "reflectionBlocks" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "itemID" TEXT REFERENCES "items"("id") ON DELETE CASCADE,
          "blockTypeRaw" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'keyInsight',
          "content" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "highlight" TEXT,
          "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "videoTimestamp" INTEGER,
          "conversationID" TEXT,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now)
        ) STRICT;
        CREATE INDEX "index_reflectionBlocks_on_itemID" ON "reflectionBlocks"("itemID");

        CREATE TABLE "conversations" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "trigger" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'userInitiated',
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "boardID" TEXT REFERENCES "boards"("id") ON DELETE SET NULL,
          "seedItemIDs" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]'
        ) STRICT;
        CREATE INDEX "index_conversations_on_boardID" ON "conversations"("boardID");

        CREATE TABLE "chatMessages" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "conversationID" TEXT REFERENCES "conversations"("id") ON DELETE CASCADE,
          "role" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'user',
          "content" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "referencedItemIDs" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
          "toolCallName" TEXT,
          "isHidden" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        ) STRICT;
        CREATE INDEX "index_chatMessages_on_conversationID" ON "chatMessages"("conversationID");

        CREATE TABLE "nudges" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "type" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'resurface',
          "targetItemID" TEXT REFERENCES "items"("id") ON DELETE CASCADE,
          "relatedItemIDs" TEXT,
          "message" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "status" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'pending',
          "scheduledFor" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now)
        ) STRICT;
        CREATE INDEX "index_nudges_on_targetItemID" ON "nudges"("targetItemID");

        CREATE TABLE "feedSources" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "feedURL" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "domain" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "title" TEXT,
          "lastFetchedAt" TEXT,
          "isEnabled" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "isAutoDiscovered" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "isUserSubscribed" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "errorCount" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now)
        ) STRICT;

        CREATE TABLE "flashcards" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "question" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "answer" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "hints" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
          "sourceItemID" TEXT,
          "sourceReflectionID" TEXT,
          "sourceTitle" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'Your flashcard',
          "sourceQuote" TEXT,
          "sourceURL" TEXT,
          "sourceLocator" TEXT,
          "boardIDs" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
          "revision" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
          "revisionStartedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "isSuspended" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "dueAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "revisionFingerprint" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "deletedAt" TEXT
        ) STRICT;

        CREATE TABLE "flashcardReviews" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "cardID" TEXT NOT NULL,
          "cardRevision" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
          "cardFingerprint" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "reviewedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now),
          "ratingRaw" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'again',
          "usedHint" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "readSource" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "sessionID" TEXT NOT NULL
        ) STRICT;
        CREATE INDEX "index_flashcardReviews_on_cardID" ON "flashcardReviews"("cardID");

        CREATE TABLE "learningPreferences" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "focusBoardIDs" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
          "sessionMinutes" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 3,
          "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT \(now)
        ) STRICT;

        CREATE TABLE "extraBoardLinks" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "itemID" TEXT NOT NULL,
          "boardID" TEXT NOT NULL
        ) STRICT;
        CREATE INDEX "index_extraBoardLinks_on_itemID" ON "extraBoardLinks"("itemID");
        CREATE INDEX "index_extraBoardLinks_on_boardID" ON "extraBoardLinks"("boardID");

        -- What a foreign key would do, for the links that can't be foreign keys.
        CREATE TRIGGER "tags_clearParentTagID" AFTER DELETE ON "tags" BEGIN
          UPDATE "tags" SET "parentTagID" = NULL WHERE "parentTagID" = old."id";
        END;
        CREATE TRIGGER "conversations_clearReflectionLinks" AFTER DELETE ON "conversations" BEGIN
          UPDATE "reflectionBlocks" SET "conversationID" = NULL WHERE "conversationID" = old."id";
        END;
        CREATE TRIGGER "items_clearExtraBoardLinks" AFTER DELETE ON "items" BEGIN
          DELETE FROM "extraBoardLinks" WHERE "itemID" = old."id";
        END;
        CREATE TRIGGER "boards_clearExtraBoardLinks" AFTER DELETE ON "boards" BEGIN
          DELETE FROM "extraBoardLinks" WHERE "boardID" = old."id";
        END;
        """
}
