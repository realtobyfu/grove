import CoreData
import Foundation
import SwiftData
import Testing
@testable import grove

/// Guards the migration limits described in `SharedModelContainer.swift`.
/// In-memory stores never migrate, so the migration tests write real stores
/// to disk.
struct SchemaMigrationTests {
    /// Entity hashes of the 2.0 schema, read from a store written by 2.0.
    private static let versionTwoHashes: [String: String] = [
        "Annotation": "00fHFaG3rIp7mpEnmpRZqXLgiYNtkgAy/kmsIRIyHBU=",
        "Board": "w5YEpRwQzICnRYTJRVNhFn+0AV+2N9txwsT/1NuoOaQ=",
        "ChatMessage": "qOC2h4qEYOnNrlLtN0XN5jmr1G5jYgRsdFfXzQ7P764=",
        "Connection": "JwRknYJmI78eVyvt4Iw47qygln2ObVJL9QaiAkCmR1w=",
        "Conversation": "QIpy4E0lSlF8cTMmVFfWmGAEoE8ECmZ4OaozcCqLgQU=",
        "FeedSource": "AtTXo3Na74h1Foex8NxgvrpK9KiqLyu6ZO/GkAW6iVw=",
        "Item": "boRl5DJekSiCYi/jnJsPGCew9HPtLwzyqfkTkzhInlo=",
        "Nudge": "vW3CqGISw24l7W5l86GdzrBHME09PKsXlUAjDy2H/QA=",
        "ReflectionBlock": "8/7g5w/I35+xW+DLWokW16txiBBtrzN/MpRRQ/B3ftk=",
        "Tag": "oozHx+mXrmd6+9TOU/TspdSkefXPJLeFh2U5X5BMSOg=",
    ]

    /// A mismatch means a stored property on a 2.0 model changed. Every
    /// synced store then has to migrate within the limits, and
    /// `LegacyStoreMigration` no longer recognizes 2.0 stores by these models.
    @Test func versionTwoModelsStillMatchTheShippedSchema() throws {
        let hashes = try model(for: SharedModelContainer.versionTwoModels).entityVersionHashesByName
        #expect(hashes.mapValues { $0.base64EncodedString() } == Self.versionTwoHashes)
    }

    @Test func modelsDeclareNoRenames() throws {
        for entity in try model(for: SharedModelContainer.models).entities {
            for property in entity.properties {
                #expect(
                    property.renamingIdentifier == property.name,
                    "\(entity.name ?? "?").\(property.name) is renamed; synced stores can't migrate past it"
                )
            }
        }
    }

    @Test func newModelsSortAfterEveryVersionTwoModel() throws {
        let existing = try model(for: SharedModelContainer.versionTwoModels).entities.compactMap(\.name)
        let last = try #require(existing.max())
        let added = try model(for: SharedModelContainer.models).entities.compactMap(\.name)
            .filter { !existing.contains($0) }
        #expect(!added.isEmpty)
        for name in added {
            #expect(name > last, "\(name) sorts before \(last), so adding it renumbers a 2.0 entity")
        }
    }

    @MainActor
    @Test func versionTwoStoreKeepsItsBoardLinks() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        try writeVersionTwoStore(at: url, recordingRenamesAs: .renamingIdentifiers)

        try expectOneLinkedBoard(at: url)
    }

    @MainActor
    @Test func preTwoStoreKeepsItsBoardLinks() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        try writeVersionTwoStore(at: url, recordingRenamesAs: .propertyNames)

        try expectOneLinkedBoard(at: url)
    }

    // MARK: - Helpers

    @MainActor
    private func expectOneLinkedBoard(at url: URL) throws {
        let container = try SharedModelContainer.openContainer(
            ModelConfiguration(schema: SharedModelContainer.schema, url: url, cloudKitDatabase: .none)
        )
        let boards = try ModelContext(container).fetch(FetchDescriptor<Legacy.Board>())
        #expect(boards.map(\.title) == ["Reading"])
        #expect(boards.first?.itemsStorage?.map(\.title) == ["Essay"])
    }

    /// Where a fixture store records the 2.0 relationship renames.
    private enum RecordedRenames {
        /// 2.0 through the Oct 2026 builds: new names, with the old names as
        /// renaming identifiers in the store's cached model.
        case renamingIdentifiers
        /// Before 2.0: the old names themselves.
        case propertyNames
    }

    /// Writes one board linked to one item, using the 2.0 entities with the
    /// renamed relationships recorded as `renames` says.
    private func writeVersionTwoStore(at url: URL, recordingRenamesAs renames: RecordedRenames) throws {
        let model = try #require(
            try model(for: SharedModelContainer.versionTwoModels).copy() as? NSManagedObjectModel
        )
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            for (name, legacyName) in LegacyStoreMigration.renamedRelationships[entity.name ?? ""] ?? [:] {
                guard let relationship = entity.relationshipsByName[name] else { continue }
                switch renames {
                case .renamingIdentifiers: relationship.renamingIdentifier = legacyName
                case .propertyNames: relationship.name = legacyName
                }
            }
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            type: .sqlite,
            at: url,
            options: [NSPersistentHistoryTrackingKey: true]
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let board = insert("Board", title: "Reading", into: context)
            let item = insert("Item", title: "Essay", into: context)
            let itemsKey = renames == .propertyNames ? "items" : "itemsStorage"
            board.setValue(NSSet(object: item), forKey: itemsKey)
            try context.save()
        }
        try coordinator.remove(store)
    }

    private func insert(_ entityName: String, title: String, into context: NSManagedObjectContext) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
        for (name, attribute) in object.entity.attributesByName where !attribute.isOptional {
            object.setValue(attribute.defaultValue, forKey: name)
        }
        object.setValue(UUID(), forKey: "id")
        object.setValue(title, forKey: "title")
        return object
    }

    private func model(for models: [any PersistentModel.Type]) throws -> NSManagedObjectModel {
        try #require(NSManagedObjectModel.makeManagedObjectModel(for: models))
    }

    private func temporaryStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Grove.store")
    }

    private func removeStore(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
