import SwiftData
import Foundation

/// Shared ModelContainer factory for both the main app and Share Extension.
///
/// Uses the App Group container (`group.dev.tuist.grove`) on iOS so the main
/// app and Share Extension can access the same on-device store. On macOS, each
/// app target uses its own sandboxed store.
enum SharedModelContainer {

    /// The SwiftData schema including all model types. Kept in one place
    /// so the main app, Share Extension, and tests always register the
    /// same set of models.
    static let schema = Schema([
        Item.self,
        Board.self,
        Tag.self,
        Connection.self,
        Annotation.self,
        ReflectionBlock.self,
        Nudge.self,
        Course.self,
        Conversation.self,
        ChatMessage.self,
        FeedSource.self,
    ])

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
        do {
            return try makeContainer(syncEnabled: SyncSettings.syncEnabled)
        } catch {
            // CloudKit may fail if not configured — fall back to local-only
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
        return try ModelContainer(for: schema, configurations: [config])
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
            return try ModelContainer(for: schema, configurations: [config])
        }
        #endif

        let config = ModelConfiguration(
            "Grove",
            schema: schema,
            cloudKitDatabase: cloudKit
        )
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
