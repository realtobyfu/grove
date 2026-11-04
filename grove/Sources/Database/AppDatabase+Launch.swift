import CloudKit
import Foundation
import SQLiteData
import SwiftData
import Synchronization

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
        try open(existingAt: databaseURL())
    }

    /// Opens the file at `url` if it's there, and creates nothing if it isn't.
    static func open(existingAt url: URL) throws -> (any DatabaseWriter)? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try open(at: url)
    }

    /// False once the library has failed to open, when `defaultDatabase` is a
    /// throwaway. Code that reaches the database without going through the UI
    /// checks this, so that it can't report saving something that will vanish.
    static var isLibraryOpen: Bool {
        libraryOpen.withLock { $0 }
    }

    private static let libraryOpen = Mutex(true)

    /// What `prepareForApp` left in place.
    struct Launch {
        /// Why the library could not open. The app must not touch the database
        /// or offer any way to add to it, because this launch runs on a throwaway
        /// copy held in memory.
        var failure: String?
        var syncEngine: SyncEngine?
        var syncFailure: String?
    }

    /// Sets the app's `defaultDatabase`. Call once, before any view exists.
    static func prepareForApp(demo: (() throws -> any DatabaseWriter)? = nil) -> Launch {
        var launch = Launch()
        do {
            try prepareDependencies {
                if let demo {
                    $0.defaultDatabase = try demo()
                    return
                }
                $0.defaultDatabase = try openForApp()
                guard SyncSettings.syncEnabled else { return }
                do {
                    let engine = try makeSyncEngine(for: $0.defaultDatabase, delegate: KeepLocalDataSyncDelegate())
                    $0.defaultSyncEngine = engine
                    launch.syncEngine = engine
                } catch {
                    databaseLog.error("Sync could not start: \(error, privacy: .public)")
                    launch.syncFailure = error.localizedDescription
                }
            }
        } catch {
            databaseLog.fault("The library could not open: \(error, privacy: .public)")
            launch.failure = error.localizedDescription
            libraryOpen.withLock { $0 = false }
            prepareDependencies {
                // Views still read the database, so something has to be there.
                $0.defaultDatabase = (try? openInMemory()) ?? (try! DatabaseQueue())
            }
        }
        return launch
    }

    /// Conversations, messages and nudges are private tables, so that a shared
    /// board never carries a person's chats. Join tables and connections have two
    /// foreign keys, which keeps them out of a share by SQLiteData's own rules.
    /// `extraBoardLinks` is deliberately missing: it never leaves this device.
    ///
    /// The engine works in its own `co.pointfree.SQLiteData.defaultZone`, so it
    /// never writes to the zone Core Data used.
    static func makeSyncEngine(
        for database: any DatabaseWriter,
        startImmediately: Bool? = nil,
        delegate: (any SyncEngineDelegate)? = nil
    ) throws -> SyncEngine {
        try SyncEngine(
            for: database,
            tables: Board.self,
            Item.self,
            ItemThumbnail.self,
            Tag.self,
            ItemTag.self,
            BoardSmartRuleTag.self,
            Connection.self,
            Annotation.self,
            ReflectionBlock.self,
            FeedSource.self,
            Flashcard.self,
            FlashcardReview.self,
            LearningPreferences.self,
            privateTables: Conversation.self,
            ChatMessage.self,
            Nudge.self,
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
