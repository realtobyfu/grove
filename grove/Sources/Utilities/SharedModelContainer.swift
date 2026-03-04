import SwiftData
import Foundation

/// Shared ModelContainer factory for both the main app and Share Extension.
///
/// Uses the App Group container (`group.dev.tuist.grove`) whenever it is
/// available so every target can resolve the same SwiftData store.
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
    /// Returns `nil` when the App Group container is unavailable (simulator
    /// without entitlements, macOS without App Groups, etc.).
    static var sharedStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("grove.store")
    }

    /// The existing sandboxed macOS store we want to preserve on first launch
    /// after moving both app targets into the App Group container.
    static var legacyMacStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(primaryMacBundleIdentifier)/Data/Library/Application Support/Grove.store")
    }

    static let primaryMacBundleIdentifier = "dev.tuist.grove"
    private static let migrationMarkerFileName = ".grove-macos-shared-store-migrated"
    private static let storeArtifactSuffixes = ["", "-shm", "-wal", "-journal"]

    // MARK: - Main App

    /// Creates a `ModelContainer` for the main app.
    ///
    /// - Uses the App Group container when available.
    /// - On macOS, first migrates the existing `dev.tuist.grove` sandbox store
    ///   into the App Group container before opening it.
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

        if let storeURL = sharedStoreURL {
            #if os(macOS)
            let preparation = try prepareMacSharedStoreIfNeeded(sharedStoreURL: storeURL)
            guard preparation == .useSharedStore else {
                let fallbackConfig = ModelConfiguration(
                    "Grove",
                    schema: schema,
                    cloudKitDatabase: cloudKit
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            }
            #endif

            let config = ModelConfiguration(
                "Grove",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: cloudKit
            )
            return try ModelContainer(for: schema, configurations: [config])
        }

        // Fallback: no App Group available (e.g. simulator without entitlements)
        let config = ModelConfiguration(
            "Grove",
            schema: schema,
            cloudKitDatabase: cloudKit
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    #if os(macOS)
    enum MacSharedStorePreparationResult: Equatable {
        case useSharedStore
        case useDefaultStore
    }

    static func prepareMacSharedStoreIfNeeded(
        fileManager: FileManager = .default,
        currentBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        legacyStoreURL: URL = legacyMacStoreURL,
        sharedStoreURL: URL
    ) throws -> MacSharedStorePreparationResult {
        let markerURL = migrationMarkerURL(for: sharedStoreURL)

        if fileManager.fileExists(atPath: markerURL.path) || storeExists(at: sharedStoreURL, fileManager: fileManager) {
            return .useSharedStore
        }

        guard currentBundleIdentifier == primaryMacBundleIdentifier else {
            return .useDefaultStore
        }

        try fileManager.createDirectory(
            at: sharedStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if storeExists(at: legacyStoreURL, fileManager: fileManager) {
            try copyStoreArtifacts(from: legacyStoreURL, to: sharedStoreURL, fileManager: fileManager)
        }

        try Data("migrated".utf8).write(to: markerURL, options: .atomic)
        return .useSharedStore
    }

    private static func migrationMarkerURL(for sharedStoreURL: URL) -> URL {
        sharedStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent(migrationMarkerFileName)
    }

    private static func storeExists(at storeURL: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: storeURL.path)
    }

    private static func copyStoreArtifacts(from sourceStoreURL: URL, to destinationStoreURL: URL, fileManager: FileManager) throws {
        for suffix in storeArtifactSuffixes {
            let sourceURL = artifactURL(for: sourceStoreURL, suffix: suffix)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            let destinationURL = artifactURL(for: destinationStoreURL, suffix: suffix)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func artifactURL(for storeURL: URL, suffix: String) -> URL {
        guard !suffix.isEmpty else {
            return storeURL
        }
        return URL(fileURLWithPath: storeURL.path + suffix)
    }
    #endif

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
