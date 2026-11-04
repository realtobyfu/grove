import SwiftData
import CoreData
import Foundation
import OSLog

private let syncLog = Logger(subsystem: "dev.tuist.grove", category: "sync")

/// Opens SwiftData stores for `LegacyStoreImporter`, which is all SwiftData does
/// in this version of the app.
enum SharedModelContainer {

    /// The SwiftData schema including all model types.
    static let schema = Schema(models)

    /// Every model type. Read "Migration Limits" below before adding one.
    static var models: [any PersistentModel.Type] {
        versionTwoModels + [
            Legacy.UserFlashcard.self,
            Legacy.UserFlashcardReview.self,
            Legacy.UserLearningPreferences.self,
        ]
    }

    /// The ten models as they shipped in 2.0. No stored property on them has
    /// changed since; `SchemaMigrationTests` pins their hashes so that stays
    /// a deliberate decision.
    static var versionTwoModels: [any PersistentModel.Type] {
        [
            Legacy.Item.self,
            Legacy.Board.self,
            Legacy.Tag.self,
            Legacy.Connection.self,
            Legacy.Annotation.self,
            Legacy.ReflectionBlock.self,
            Legacy.Nudge.self,
            Legacy.Conversation.self,
            Legacy.ChatMessage.self,
            Legacy.FeedSource.self,
        ]
    }

    /// URL of the shared SwiftData store inside the App Group container, or
    /// `nil` when the App Group container is unavailable.
    static var sharedStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppDatabase.appGroupIdentifier)?
            .appendingPathComponent("grove.store")
    }

    /// Opens the store, first bringing a pre-2.0 store up to date. Internal so
    /// tests open stores exactly as the app does.
    static func openContainer(_ config: ModelConfiguration) throws -> ModelContainer {
        try LegacyStoreMigration.migrateIfNeeded(storeURL: config.url)
        return try ModelContainer(for: schema, configurations: [config])
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
