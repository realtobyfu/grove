import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ItemReaderViewModel {
    // MARK: - Dependencies

    var item: Item
    var modelContext: ModelContext
    var onNavigateToItem: ((Item) -> Void)?

    // MARK: - Business State

    var isEditingContent = false
    var showArticleWebView = false
    var isEditingSummary = false
    var editableSummary = ""
    var isReflectionPanelCollapsed = false
    var editingBlock: ReflectionBlock?
    var showReflectionEditor = false
    var blockToDelete: ReflectionBlock?

    // MARK: - Video State

    var videoCurrentTime: Double = 0
    var videoDuration: Double = 0
    var videoSeekTarget: Double? = nil

    // MARK: - Zoom State

    var webViewZoomLevel: CGFloat = 1.0

    // MARK: - Find State

    var showFindBar = false
    var findQuery = ""
    var findMatchCount = 0
    var findCurrentMatch = 0
    var findForwardToken = 0
    var findBackwardToken = 0

    // MARK: - Init

    init(item: Item, modelContext: ModelContext, onNavigateToItem: ((Item) -> Void)? = nil) {
        self.item = item
        self.modelContext = modelContext
        self.onNavigateToItem = onNavigateToItem
    }

    // MARK: - Computed Properties

    var sortedReflections: [ReflectionBlock] {
        item.reflections.sorted { $0.position < $1.position }
    }

    var isVideoItem: Bool {
        item.type == .video && localVideoURL != nil
    }

    /// URL that can be loaded in the in-app WebView (article items only, not local video).
    var articleURL: URL? {
        guard item.type == .article,
              item.metadata["videoLocalFile"] != "true" else { return nil }

        return resolvedSourceURL(from: item.sourceURL)
    }

    /// Resolve the local video file URL for this item
    var localVideoURL: URL? {
        guard item.type == .video else { return nil }
        if let path = item.metadata["originalPath"] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return url
            }
        }
        if let urlString = item.sourceURL, urlString.hasPrefix("file://"),
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    var scoreBreakdownTooltip: String {
        let breakdown = item.scoreBreakdown
        if breakdown.isEmpty {
            return "\(item.growthStage.displayName) -- 0 pts"
        }
        let lines = breakdown.map { "\($0.label): +\($0.points)" }
        return "\(item.growthStage.displayName) -- \(item.depthScore) pts\n" + lines.joined(separator: "\n")
    }

    // MARK: - Zoom

    func zoomIn() {
        webViewZoomLevel = min(webViewZoomLevel + 0.1, 2.0)
    }

    func zoomOut() {
        webViewZoomLevel = max(webViewZoomLevel - 0.1, 0.5)
    }

    func resetZoom() {
        webViewZoomLevel = 1.0
    }

    var zoomPercentage: Int {
        Int(round(webViewZoomLevel * 100))
    }

    // MARK: - Find Bar

    func closeFindBar() {
        showFindBar = false
        findQuery = ""
        findMatchCount = 0
        findCurrentMatch = 0
    }

    // MARK: - Reflection Editor

    func openBlockForEditing(_ block: ReflectionBlock, focusTrigger: @escaping () -> Void) {
        if isReflectionPanelCollapsed { isReflectionPanelCollapsed = false }
        editingBlock = block
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = true
        }
        NotificationCenter.default.post(name: .groveEnterFocusMode, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focusTrigger()
        }
    }

    func openReflectionEditor(type: ReflectionBlockType, content: String, highlight: String?, focusTrigger: @escaping () -> Void) {
        if isReflectionPanelCollapsed { isReflectionPanelCollapsed = false }
        let nextPosition = (sortedReflections.last?.position ?? -1) + 1
        let timestamp: Int? = isVideoItem ? Int(videoCurrentTime) : nil
        let block = ReflectionBlock(
            item: item,
            blockType: type,
            content: content,
            highlight: highlight,
            position: nextPosition,
            videoTimestamp: timestamp
        )
        modelContext.insert(block)
        item.reflections.append(block)
        editingBlock = block
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = true
        }
        NotificationCenter.default.post(name: .groveEnterFocusMode, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focusTrigger()
        }
    }

    func closeReflectionEditor() {
        if let block = editingBlock {
            let trimmed = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Empty block -- clean up orphan
                item.reflections.removeAll { $0.id == block.id }
                modelContext.delete(block)
                item.updatedAt = .now
            } else {
                item.updatedAt = .now
            }
            try? modelContext.save()
        }
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = false
        }
        editingBlock = nil
        NotificationCenter.default.post(name: .groveExitFocusMode, object: nil)
    }

    // MARK: - Block CRUD

    func deleteBlock(_ block: ReflectionBlock) {
        withAnimation(.easeOut(duration: 0.25)) {
            item.reflections.removeAll { $0.id == block.id }
            modelContext.delete(block)
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    func requestDeleteBlock(_ block: ReflectionBlock) -> Bool {
        blockToDelete = block
        return true
    }

    func confirmDeleteBlock() {
        if let block = blockToDelete {
            deleteBlock(block)
        }
        blockToDelete = nil
    }

    func cancelDeleteBlock() {
        blockToDelete = nil
    }

    // MARK: - Summary Editing

    func beginEditingSummary(currentSummary: String) {
        editableSummary = currentSummary
        isEditingSummary = true
    }

    func finishEditingSummary() {
        let trimmed = editableSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.metadata["summary"] = String(trimmed.prefix(120))
        }
        isEditingSummary = false
        try? modelContext.save()
    }

    // MARK: - Review Banner

    func acceptReview() {
        item.metadata["summaryReviewPending"] = nil
        item.metadata["overviewReviewPending"] = nil
        try? modelContext.save()
    }

    func revertOverview() {
        if let original = item.metadata["originalDescription"], !original.isEmpty {
            item.content = original
            item.metadata["hasLLMOverview"] = nil
            item.metadata["overviewReviewPending"] = nil
            item.metadata["originalDescription"] = nil
            try? modelContext.save()
        }
    }

    func dismissReview() {
        item.metadata["summaryReviewPending"] = nil
        item.metadata["overviewReviewPending"] = nil
        try? modelContext.save()
    }

    // MARK: - Content Editing

    func toggleContentEditing() {
        let wasEditing = isEditingContent
        isEditingContent.toggle()
        if wasEditing {
            if item.metadata["isAIGenerated"] == "true" && item.metadata["isAIEdited"] != "true" {
                item.metadata["isAIEdited"] = "true"
            }
        }
    }

    // MARK: - Wiki-Link Navigation

    func navigateToItemByTitle(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let allItems: [Item] = modelContext.fetchAll()
        if let matchedItem = allItems.first(where: { $0.title.localizedCaseInsensitiveCompare(trimmedTitle) == .orderedSame }) {
            onNavigateToItem?(matchedItem)
        }
    }

    // MARK: - Thumbnail Backfill

    /// Downloads cover image for existing items that have a thumbnailURL but no stored thumbnail.
    func backfillThumbnailIfNeeded() {
        guard item.thumbnail == nil,
              let thumbnailURL = item.metadata["thumbnailURL"],
              !thumbnailURL.isEmpty else { return }
        Task {
            if let imageData = await ImageDownloadService.shared.downloadAndCompress(urlString: thumbnailURL) {
                item.thumbnail = imageData
                try? modelContext.save()
            }
        }
    }

    // MARK: - Item Change Reset

    func resetOnItemChange() {
        isEditingContent = false
        if showReflectionEditor { closeReflectionEditor() }
        showArticleWebView = false
        isEditingSummary = false
        editableSummary = ""
        isReflectionPanelCollapsed = false
        webViewZoomLevel = 1.0
        closeFindBar()
    }
}
