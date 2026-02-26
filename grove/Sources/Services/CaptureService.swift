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
    private let metadataFetcher: URLMetadataFetcherProtocol
    private let imageDownloader: ImageDownloadServiceProtocol

    init(
        modelContext: ModelContext,
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared
    ) {
        self.modelContext = modelContext
        self.metadataFetcher = metadataFetcher
        self.imageDownloader = imageDownloader
    }

    /// Quick capture: detects URL vs plain text, creates appropriate Item.
    /// For URL items, metadata is fetched asynchronously after creation.
    /// Auto-tagging runs as a background Task if AI is enabled.
    func captureItem(input: String) -> Item {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()),
           url.host != nil {
            // URL input — detect codebase (GitHub) vs video vs article
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

            // Fetch metadata asynchronously — does not block capture
            let itemID = item.id
            let context = self.modelContext
            Task {
                guard let metadata = await self.metadataFetcher.fetch(urlString: trimmed) else {
                    // Clear loading flag even on failure
                    let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
                    if let fetchedItem = try? context.fetch(desc).first {
                        fetchedItem.metadata["fetchingMetadata"] = nil
                        try? context.save()
                    }
                    return
                }
                // Re-fetch the item from context by ID
                let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
                guard let fetchedItem = try? context.fetch(descriptor).first else { return }

                if let title = metadata.title {
                    fetchedItem.title = title
                }
                if let description = metadata.description {
                    fetchedItem.content = description
                }
                // Prefer LP image data (works on bot-protected sites), fall back to URL download
                if let rawImageData = metadata.imageData,
                   let compressed = self.imageDownloader.compressImageData(rawImageData) {
                    fetchedItem.thumbnail = compressed
                } else if let imageURLString = metadata.imageURL {
                    fetchedItem.metadata["thumbnailURL"] = imageURLString
                    if let imageData = await self.imageDownloader.downloadAndCompress(urlString: imageURLString) {
                        fetchedItem.thumbnail = imageData
                    }
                }
                fetchedItem.metadata["fetchingMetadata"] = nil
                fetchedItem.updatedAt = .now
                try? context.save()

                // Auto-tag after metadata is available (better LLM input)
                await self.autoTagItem(itemID: itemID, context: context)

                // Set summary review flag if auto-tag generated a summary
                if fetchedItem.metadata["summary"] != nil {
                    fetchedItem.metadata["summaryReviewPending"] = "true"
                    try? context.save()
                }

                // Generate LLM overview for articles
                if itemType == .article {
                    await self.generateOverview(
                        itemID: itemID,
                        context: context,
                        title: metadata.title ?? trimmed,
                        description: metadata.description,
                        bodyText: metadata.bodyText
                    )

                    // Fallback: if still no summary but overview was generated, extract from overview
                    let desc2 = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
                    if let updatedItem = try? context.fetch(desc2).first,
                       updatedItem.metadata["summary"] == nil,
                       let overviewContent = updatedItem.content, !overviewContent.isEmpty {
                        let firstSentence = overviewContent
                            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
                            .first?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !firstSentence.isEmpty {
                            updatedItem.metadata["summary"] = String(firstSentence.prefix(120))
                            try? context.save()
                        }
                    }
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

            // Auto-tag plain text items immediately (content already available)
            let itemID = item.id
            let context = self.modelContext
            Task {
                await self.autoTagItem(itemID: itemID, context: context)
            }

            return item
        }
    }

    // MARK: - Auto-Tagging

    /// Runs auto-tagging on an item as a background operation.
    /// If AI is configured, calls AutoTagService (which handles board suggestions via notification).
    /// If AI is not configured but no boards exist (cold start), posts a heuristic board suggestion.
    private func autoTagItem(itemID: UUID, context: ModelContext) async {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }

        if LLMServiceConfig.isConfigured {
            let service = AutoTagService()
            await service.tagItem(item, in: context)
        } else {
            // Cold start heuristic: if no boards exist and this is one of the first captures,
            // suggest a board name derived from the item's title
            let boardDescriptor = FetchDescriptor<Board>()
            let allBoards = (try? context.fetch(boardDescriptor)) ?? []
            guard allBoards.isEmpty else { return }

            // Only suggest on first 3 captures
            let captureCount = UserDefaults.standard.integer(forKey: "grove.coldStartCaptureCount")
            guard captureCount < 3 else { return }
            UserDefaults.standard.set(captureCount + 1, forKey: "grove.coldStartCaptureCount")

            // Derive a board name from the item title (first 2-3 words, title-cased)
            let words = item.title
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .prefix(3)
            let suggestedName = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            guard !suggestedName.isEmpty else { return }

            let suggestionEngine = BoardSuggestionEngine()
            let decision = suggestionEngine.resolveSuggestion(
                for: item,
                suggestedName: suggestedName,
                boards: allBoards
            )
            BoardSuggestionMetadata.apply(decision, to: item)
            try? context.save()

            NotificationCenter.default.post(
                name: .groveNewBoardSuggestion,
                object: nil,
                userInfo: BoardSuggestionMetadata.notificationUserInfo(
                    itemID: item.id,
                    decision: decision,
                    isColdStart: true
                )
            )
        }
    }

    // MARK: - Overview Generation

    /// Generates a multi-paragraph overview/summary for an article using the LLM.
    /// Stores the result in item.content, replacing the short OG description.
    private func generateOverview(
        itemID: UUID,
        context: ModelContext,
        title: String,
        description: String?,
        bodyText: String?
    ) async {
        guard LLMServiceConfig.isConfigured else { return }

        // Need at least some text to summarize
        let sourceText = bodyText ?? description ?? ""
        guard sourceText.count > 20 else { return }

        let systemPrompt = """
        You are a knowledge-management assistant. Given an article's title and text, \
        write a concise overview (2-3 short paragraphs) that captures the key ideas, \
        arguments, and takeaways. Write in plain prose, no bullet points or headers. \
        Return only the overview text, nothing else.
        """

        let userPrompt = """
        Title: \(title)

        Article text:
        \(String(sourceText.prefix(4000)))
        """

        let provider = LLMServiceConfig.makeProvider()
        guard let result = await provider.complete(
            system: systemPrompt,
            user: userPrompt,
            service: "overview"
        ) else { return }

        let overview = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overview.isEmpty else { return }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }

        // Save original description before replacing with overview
        if let original = item.content, !original.isEmpty {
            item.metadata["originalDescription"] = original
        }
        item.content = overview
        item.metadata["hasLLMOverview"] = "true"
        item.metadata["overviewReviewPending"] = "true"
        item.updatedAt = .now
        try? context.save()
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
        Task {
            let fileURL = URL(fileURLWithPath: filePath)

            // Extract metadata
            let meta = await VideoThumbnailGenerator.extractMetadata(for: fileURL)

            // Generate thumbnail
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

            // Auto-tag after video metadata is available
            await self.autoTagItem(itemID: itemID, context: context)
        }

        return item
    }

    /// Check if a file path points to a supported video file
    nonisolated static func isSupportedVideoFile(_ path: String) -> Bool {
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

    private static func isGitHubURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" || host == "www.github.com"
    }
}
