import CloudKit
import Foundation
import SQLiteData
import SwiftData

extension AppDatabase {
    /// The store the SwiftData build of this install used.
    static func legacyStoreURL() -> URL {
        #if os(iOS)
        if let shared = SharedModelContainer.sharedStoreURL { return shared }
        #endif
        return ModelConfiguration("Grove", schema: SharedModelContainer.schema, cloudKitDatabase: .none).url
    }

    /// Opens the library for the app, importing the SwiftData store the first
    /// time. A throw means no database was left behind, so the next launch tries
    /// the import again.
    static func openForApp() throws -> any DatabaseWriter {
        let url = try databaseURL()
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            let source = legacyStoreURL()
            if FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) {
                let report = try LegacyStoreImporter.run(source: source, destination: url)
                databaseLog.notice("Imported the SwiftData store: \(report.rowCounts, privacy: .public)")
                if !report.duplicatesDropped.isEmpty {
                    databaseLog.notice("Dropped rows repeating an ID: \(report.duplicatesDropped, privacy: .public)")
                }
            }
        }
        return try open(at: url)
    }

    /// Opens the library without creating it, or returns `nil` if the app has not
    /// run yet. The Share Extension must use this: `openForApp` decides whether to
    /// import by whether the file exists, so creating it here would abandon the
    /// SwiftData library.
    static func openExistingForExtension() throws -> (any DatabaseWriter)? {
        let url = try databaseURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try open(at: url)
    }

    /// Conversations, messages and nudges are private tables, so that a shared
    /// board never carries a person's chats. Join tables and connections have two
    /// foreign keys, which keeps them out of a share by SQLiteData's own rules.
    /// `extraBoardLinks` is deliberately missing: it never leaves this device.
    static func makeSyncEngine(
        for database: any DatabaseWriter,
        startImmediately: Bool? = nil,
        delegate: (any SyncEngineDelegate)? = nil
    ) throws -> SyncEngine {
        try SyncEngine(
            for: database,
            tables: DB.Board.self,
            DB.Item.self,
            DB.ItemThumbnail.self,
            DB.Tag.self,
            DB.ItemTag.self,
            DB.BoardSmartRuleTag.self,
            DB.Connection.self,
            DB.Annotation.self,
            DB.ReflectionBlock.self,
            DB.FeedSource.self,
            DB.Flashcard.self,
            DB.FlashcardReview.self,
            DB.LearningPreferences.self,
            privateTables: DB.Conversation.self,
            DB.ChatMessage.self,
            DB.Nudge.self,
            containerIdentifier: "iCloud.dev.tuist.grove",
            startImmediately: startImmediately,
            delegate: delegate
        )
    }
}

/// Stops SyncEngine erasing the library when iCloud signs out. By default it
/// deletes every synced table on sign-out or an account switch, which would take
/// the only copy of anything not yet uploaded.
final class KeepLocalDataSyncDelegate: SyncEngineDelegate {
    func syncEngine(
        _ syncEngine: SyncEngine,
        accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
    ) async {
        switch changeType {
        case .signOut, .switchAccounts:
            syncEngine.stop()
            databaseLog.notice("iCloud account changed: stopped syncing and kept the library")
        case .signIn:
            break
        @unknown default:
            break
        }
    }
}
