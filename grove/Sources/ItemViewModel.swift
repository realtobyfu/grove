import Foundation
import SwiftData
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@Observable
final class ItemViewModel {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createNote(title: String = "Untitled Note") -> Item {
        let item = Item(title: title, type: .note)
        item.status = .active
        modelContext.insert(item)
        try? modelContext.save()
        return item
    }

    func assignToBoard(_ item: Item, board: Board) {
        if !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    func removeFromBoard(_ item: Item, board: Board) {
        item.boards.removeAll { $0.id == board.id }
        item.updatedAt = .now
        try? modelContext.save()
    }

    func updateItem(_ item: Item, title: String, content: String?) {
        item.title = title
        item.content = content
        item.updatedAt = .now
        try? modelContext.save()
    }

    func deleteItem(_ item: Item) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    /// Quick capture: detects URL vs plain text, creates appropriate Item.
    /// For URL items, metadata is fetched asynchronously after creation.
    func captureItem(input: String) -> Item {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()),
           url.host != nil {
            // URL input — detect article vs video
            let itemType: ItemType = Self.isVideoURL(trimmed) ? .video : .article
            let item = Item(title: trimmed, type: itemType)
            item.status = .inbox
            item.sourceURL = trimmed
            modelContext.insert(item)
            try? modelContext.save()

            // Fetch metadata asynchronously — does not block capture
            let itemID = item.id
            let context = self.modelContext
            Task.detached {
                guard let metadata = await URLMetadataFetcher.shared.fetch(urlString: trimmed) else {
                    return
                }
                await MainActor.run {
                    // Re-fetch the item from context by ID
                    let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
                    guard let fetchedItem = try? context.fetch(descriptor).first else { return }

                    if let title = metadata.title {
                        fetchedItem.title = title
                    }
                    if let description = metadata.description {
                        fetchedItem.content = description
                    }
                    if let imageURLString = metadata.imageURL {
                        // Store the thumbnail URL in metadata for now;
                        // actual image data download can be added later
                        fetchedItem.metadata["thumbnailURL"] = imageURLString
                    }
                    fetchedItem.updatedAt = .now
                    try? context.save()
                }
            }

            return item
        } else {
            // Plain text — create a note
            let title = String(trimmed.prefix(80))
            let item = Item(title: title, type: .note)
            item.status = .inbox
            item.content = trimmed
            modelContext.insert(item)
            try? modelContext.save()
            return item
        }
    }

    // MARK: - Connections

    func createConnection(source: Item, target: Item, type: ConnectionType) -> Connection {
        let connection = Connection(sourceItem: source, targetItem: target, type: type)
        modelContext.insert(connection)
        source.outgoingConnections.append(connection)
        target.incomingConnections.append(connection)
        source.updatedAt = .now
        target.updatedAt = .now
        try? modelContext.save()
        return connection
    }

    func deleteConnection(_ connection: Connection) {
        if let source = connection.sourceItem {
            source.outgoingConnections.removeAll { $0.id == connection.id }
            source.updatedAt = .now
        }
        if let target = connection.targetItem {
            target.incomingConnections.removeAll { $0.id == connection.id }
            target.updatedAt = .now
        }
        modelContext.delete(connection)
        try? modelContext.save()
    }

    /// Find items matching a search query (for fuzzy-search in connection/wiki-link pickers)
    func searchItems(query: String, excluding: Item? = nil) -> [Item] {
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return [] }
        let filtered = allItems.filter { item in
            if let excluding, item.id == excluding.id { return false }
            if query.isEmpty { return true }
            return item.title.localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.prefix(20))
    }

    // MARK: - Local Video Import

    /// Supported video file extensions
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "mkv", "m4v", "avi"]

    /// Supported UTTypes for video drag-and-drop
    static var supportedVideoUTTypes: [UTType] {
        [.mpeg4Movie, .quickTimeMovie, .movie, .video, .avi]
    }

    /// Create a video item from a local file path. The file is referenced, not copied.
    func createVideoItem(filePath: String, board: Board? = nil) -> Item {
        let url = URL(fileURLWithPath: filePath)
        let filename = url.deletingPathExtension().lastPathComponent
        let item = Item(title: filename, type: .video)
        item.status = .inbox
        item.sourceURL = url.absoluteString // file:// URL
        item.metadata["videoLocalFile"] = "true"
        item.metadata["originalPath"] = filePath
        modelContext.insert(item)
        if let board = board {
            item.boards.append(board)
        }
        try? modelContext.save()

        // Extract metadata and thumbnail asynchronously
        let itemID = item.id
        let context = self.modelContext
        Task.detached {
            let fileURL = URL(fileURLWithPath: filePath)

            // Extract metadata
            let meta = await VideoThumbnailGenerator.extractMetadata(for: fileURL)

            // Generate thumbnail
            let thumbnailData = await VideoThumbnailGenerator.generateThumbnail(for: fileURL)

            await MainActor.run {
                let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
                guard let fetchedItem = try? context.fetch(descriptor).first else { return }

                for (key, value) in meta {
                    fetchedItem.metadata[key] = value
                }
                if let thumbnailData = thumbnailData {
                    fetchedItem.thumbnail = thumbnailData
                }
                fetchedItem.updatedAt = .now
                try? context.save()
            }
        }

        return item
    }

    /// Check if a file path points to a supported video file
    static func isSupportedVideoFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return supportedVideoExtensions.contains(ext)
    }

    private static func isVideoURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains("youtube.com/watch")
            || lower.contains("youtu.be/")
            || lower.contains("vimeo.com/")
            || lower.contains("twitch.tv/")
    }
}
