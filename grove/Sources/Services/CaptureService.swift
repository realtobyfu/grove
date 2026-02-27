import Foundation
import SwiftData
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
protocol CaptureServiceProtocol {
    func captureItem(input: String) -> Item
    func createVideoItem(filePath: String, board: Board?) -> Item
}

@MainActor
@Observable
final class CaptureService: CaptureServiceProtocol {
    private var modelContext: ModelContext
    private let enricher: ItemMetadataEnricher
    private let tagger: ItemAutoTagger

    init(
        modelContext: ModelContext,
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared,
        onBoardSuggestion: BoardSuggestionCallback? = nil
    ) {
        self.modelContext = modelContext
        self.enricher = ItemMetadataEnricher(
            metadataFetcher: metadataFetcher,
            imageDownloader: imageDownloader
        )
        self.tagger = ItemAutoTagger(onBoardSuggestion: onBoardSuggestion)
    }

    /// Quick capture: detects URL vs plain text, creates appropriate Item.
    /// Metadata fetching and auto-tagging run asynchronously after creation.
    func captureItem(input: String) -> Item {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()),
           url.host != nil {
            return captureURLItem(trimmed)
        } else {
            return captureTextItem(trimmed)
        }
    }

    // MARK: - URL Capture

    private func captureURLItem(_ trimmed: String) -> Item {
        let itemType: ItemType
        if Self.isGitHubURL(trimmed) {
            itemType = .codebase
        } else if Self.isVideoURL(trimmed) {
            itemType = .video
        } else {
            itemType = .article
        }

        let item = Item(title: trimmed, type: itemType)
        item.status = .inbox
        item.sourceURL = trimmed
        item.metadata["fetchingMetadata"] = "true"
        modelContext.insert(item)
        try? modelContext.save()

        let itemID = item.id
        let context = self.modelContext
        let enricher = self.enricher
        let tagger = self.tagger

        Task {
            let meta = await enricher.enrichURLItem(
                itemID: itemID,
                urlString: trimmed,
                context: context
            )

            // Auto-tag after metadata is available
            await tagger.autoTagItem(itemID: itemID, context: context)

            // Mark summary review if needed
            enricher.markSummaryReviewIfNeeded(itemID: itemID, context: context)

            // Generate LLM overview for articles
            if itemType == .article {
                await enricher.generateOverview(
                    itemID: itemID,
                    context: context,
                    title: meta.title ?? trimmed,
                    description: meta.description,
                    bodyText: meta.bodyText
                )
                enricher.extractSummaryFallback(itemID: itemID, context: context)
            }
        }

        return item
    }

    // MARK: - Text Capture

    private func captureTextItem(_ trimmed: String) -> Item {
        let title = String(trimmed.prefix(80))
        let item = Item(title: title, type: .note)
        item.status = .inbox
        item.content = trimmed
        modelContext.insert(item)
        try? modelContext.save()

        let itemID = item.id
        let context = self.modelContext
        let tagger = self.tagger

        Task {
            await tagger.autoTagItem(itemID: itemID, context: context)
        }

        return item
    }

    // MARK: - Local Video Import

    /// Supported video file extensions
    nonisolated static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "mkv", "m4v", "avi"]

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
        item.sourceURL = url.absoluteString
        item.metadata["videoLocalFile"] = "true"
        item.metadata["originalPath"] = filePath
        modelContext.insert(item)
        if let board = board {
            item.boards.append(board)
        }
        try? modelContext.save()

        let itemID = item.id
        let context = self.modelContext
        let tagger = self.tagger

        Task {
            let fileURL = URL(fileURLWithPath: filePath)
            let meta = await VideoThumbnailGenerator.extractMetadata(for: fileURL)
            let thumbnailData = await VideoThumbnailGenerator.generateThumbnail(for: fileURL)

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

            await tagger.autoTagItem(itemID: itemID, context: context)
        }

        return item
    }

    /// Check if a file path points to a supported video file
    nonisolated static func isSupportedVideoFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return supportedVideoExtensions.contains(ext)
    }

    // MARK: - URL Detection Helpers

    private static func isVideoURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains("youtube.com/watch")
            || lower.contains("youtu.be/")
            || lower.contains("vimeo.com/")
            || lower.contains("twitch.tv/")
    }

    private static func isGitHubURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" || host == "www.github.com"
    }
}
