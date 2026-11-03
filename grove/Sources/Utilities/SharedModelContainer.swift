import SwiftData
import CoreData
import Foundation
import OSLog

private let syncLog = Logger(subsystem: "dev.tuist.grove", category: "sync")

/// The SwiftData models. Nesting does not change their entity names, which
/// `SchemaMigrationTests` pins, so stores written before this namespace existed
/// still open.
enum Legacy {}

/// Shared ModelContainer factory for both the main app and Share Extension.
///
/// Uses the App Group container (`group.dev.tuist.grove`) on iOS so the main
/// app and Share Extension can access the same on-device store. On macOS, each
/// app target uses its own sandboxed store.
enum SharedModelContainer {

    /// The SwiftData schema including all model types. Kept in one place
    /// so the main app, Share Extension, and tests always register the
    /// same set of models.
    static let schema = Schema(models)

    /// Every model type. Read "Migration Limits" below before adding one.
    static var models: [any PersistentModel.Type] {
        versionTwoModels + [
            UserFlashcard.self,
            UserFlashcardReview.self,
            UserLearningPreferences.self,
        ]
    }

    /// The ten models as they shipped in 2.0. No stored property on them has
    /// changed since; `SchemaMigrationTests` pins their hashes so that stays
    /// a deliberate decision.
    static var versionTwoModels: [any PersistentModel.Type] {
        [
            Item.self,
            Board.self,
            Tag.self,
            Connection.self,
            Annotation.self,
            ReflectionBlock.self,
            Nudge.self,
            Conversation.self,
            ChatMessage.self,
            FeedSource.self,
        ]
    }

    /// App Group identifier shared between main app and Share Extension.
    static let appGroupIdentifier = "group.dev.tuist.grove"

    /// URL for the shared SwiftData store inside the App Group container.
    /// Returns `nil` when the App Group container is unavailable.
    static var sharedStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("grove.store")
    }

    // MARK: - Main App

    /// Creates a `ModelContainer` for the main app.
    ///
    /// - On iOS, uses the App Group container when available so the Share
    ///   Extension can access the same on-device data.
    /// - On macOS, uses the target's default sandbox store.
    /// - CloudKit sync is conditional on `SyncSettings.syncEnabled`.
    /// - If CloudKit initialization fails, falls back to a local-only store
    ///   and disables sync to prevent repeated failures.
    static func makeForApp() -> ModelContainer {
        let wantsSync = SyncSettings.syncEnabled
        do {
            return try makeContainer(syncEnabled: wantsSync)
        } catch {
            if wantsSync {
                // CloudKit setup failed (e.g. account unavailable, entitlement or
                // schema mismatch). Fall back to local-only so the app still opens,
                // but log loudly so the failure is diagnosable instead of silent.
                syncLog.error("CloudKit container init failed, falling back to local-only: \(error, privacy: .public)")
            }
            do {
                let container = try makeContainer(syncEnabled: false)
                SyncSettings.syncEnabled = false
                return container
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    // MARK: - Share Extension

    /// Creates a `ModelContainer` for the Share Extension.
    ///
    /// Always local-only (no CloudKit) to stay within the extension's 120 MB
    /// memory limit. Uses the App Group container URL so writes are visible
    /// to the main app.
    static func makeForExtension() throws -> ModelContainer {
        guard let storeURL = sharedStoreURL else {
            throw ContainerError.appGroupUnavailable
        }

        let config = ModelConfiguration(
            "Grove",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try openContainer(config)
    }

    // MARK: - Private

    private static func makeContainer(syncEnabled: Bool) throws -> ModelContainer {
        let cloudKit: ModelConfiguration.CloudKitDatabase = syncEnabled ? .automatic : .none

        #if os(iOS)
        if let storeURL = sharedStoreURL {
            let config = ModelConfiguration(
                "Grove",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: cloudKit
            )
            return try openContainer(config)
        }
        #endif

        let config = ModelConfiguration(
            "Grove",
            schema: schema,
            cloudKitDatabase: cloudKit
        )
        return try openContainer(config)
    }

    /// Opens the store, first bringing a pre-2.0 store up to date. Internal so
    /// tests open stores exactly as the app does.
    static func openContainer(_ config: ModelConfiguration) throws -> ModelContainer {
        try LegacyStoreMigration.migrateIfNeeded(storeURL: config.url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    enum ContainerError: Error, LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "App Group container '\(appGroupIdentifier)' is not available."
            }
        }
    }
}

// MARK: - Migration Limits
//
// Every store written since 2.0 can sync, and a synced store only survives a
// migration within two limits:
//
// - No renames. CloudKit refuses to migrate a store whose model declares any
//   `originalName`, even with sync off (error 134110).
// - No renumbering. Core Data numbers entities alphabetically, and stores
//   written by 2.0 through the Oct 2026 builds recorded the 2.0 renames in
//   their cached model. Migrating one while an entity in a many-to-many
//   relationship changes number fails (`no such column: Z_9ITEMSSTORAGE`).
//   So a new model's class name must sort after every existing one — the
//   learning models are `User…` for that reason, with typealiases for call
//   sites.
//
// `SchemaMigrationTests` checks both. Stores from before 2.0 are handled by
// `LegacyStoreMigration`.

// MARK: - Pre-2.0 Stores

/// Brings a pre-2.0 store up to the current schema without losing its links.
///
/// 2.0 renamed every to-many relationship (`items` → `itemsStorage`, ...), and
/// inferred migration only carries a relationship across a rename when the
/// destination declares the old name as its renaming identifier. The models
/// can't declare it, since that blocks every synced store, so the renames are
/// applied here — and only to pre-2.0 stores, which never synced because
/// CloudKit could not load their model.
enum LegacyStoreMigration {
    /// Current name → pre-2.0 name of each renamed relationship, by entity.
    static let renamedRelationships: [String: [String: String]] = [
        "Board": [
            "itemsStorage": "items",
            "smartRuleTagsStorage": "smartRuleTags",
        ],
        "Item": [
            "boardsStorage": "boards",
            "tagsStorage": "tags",
            "annotationsStorage": "annotations",
            "reflectionsStorage": "reflections",
            "outgoingConnectionsStorage": "outgoingConnections",
            "incomingConnectionsStorage": "incomingConnections",
        ],
        "Tag": [
            "childTagsStorage": "childTags",
            "itemsStorage": "items",
            "smartRuleBoardsStorage": "smartRuleBoards",
        ],
        "Conversation": [
            "messagesStorage": "messages",
            "createdReflectionsStorage": "createdReflections",
        ],
    ]

    /// Migrates the store at `storeURL` in place unless it was written by 2.0
    /// or later. A missing store is left for SwiftData to create.
    static func migrateIfNeeded(storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        for models in [SharedModelContainer.versionTwoModels, SharedModelContainer.models] {
            let model = try managedObjectModel(for: models)
            if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) { return }
        }

        // SwiftData may hand back a model it is already using, which is
        // immutable, so the renames go on a copy.
        guard let model = try managedObjectModel(for: SharedModelContainer.models).copy() as? NSManagedObjectModel else {
            throw MigrationError.modelUnavailable
        }
        for (entityName, renames) in renamedRelationships {
            guard let entity = model.entitiesByName[entityName] else { continue }
            for (name, legacyName) in renames {
                entity.relationshipsByName[name]?.renamingIdentifier = legacyName
            }
        }

        // SwiftData tracks persistent history; opening such a store without
        // the key makes Core Data fall back to read-only and the migration fail.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            type: .sqlite,
            at: storeURL,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
                NSPersistentHistoryTrackingKey: true,
            ]
        )
        try coordinator.remove(store)
        syncLog.info("Migrated a pre-2.0 store using its legacy relationship names")
    }

    private static func managedObjectModel(for models: [any PersistentModel.Type]) throws -> NSManagedObjectModel {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else {
            throw MigrationError.modelUnavailable
        }
        return model
    }

    enum MigrationError: Error {
        case modelUnavailable
    }
}
