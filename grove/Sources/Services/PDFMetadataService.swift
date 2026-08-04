import Foundation
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What a downloaded PDF could tell us about itself.
struct PDFExtractedMetadata: Sendable {
    var title: String?
    var author: String?
    var thumbnailData: Data?
    var cachedFileURL: URL
}

/// Downloads a PDF, caches it on disk, and pulls title/author/cover out of it.
///
/// A PDF has no OpenGraph tags, so the only metadata worth having lives in the
/// document itself. The cached copy is what the reader opens later, so the
/// download is not wasted work.
enum PDFMetadataService {

    /// Anything past this is a document dump, not an article — refuse it rather
    /// than filling the cache directory with it.
    private static let maxBytes = 100 * 1024 * 1024
    private static let timeout: TimeInterval = 30
    private static let thumbnailWidth: CGFloat = 600

    // MARK: - Cache

    private static var cacheDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("GrovePDFCache", isDirectory: true)
    }

    private static func cacheURL(for itemID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(itemID.uuidString).pdf")
    }

    /// The on-disk PDF for an item, or nil when nothing has been cached.
    static func cachedFileURL(itemID: UUID) -> URL? {
        let url = cacheURL(for: itemID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func removeCachedFile(itemID: UUID) {
        try? FileManager.default.removeItem(at: cacheURL(for: itemID))
    }

    // MARK: - Download + Extract

    /// One download per item, however many callers ask for it.
    ///
    /// The enricher and the reader both reach for the same file the moment an
    /// item is captured and opened; without this they raced to write the same
    /// cache path twice.
    @MainActor
    private static var inFlight: [UUID: Task<PDFExtractedMetadata?, Never>] = [:]

    /// Returns nil on any network, size, or parse failure.
    static func downloadAndExtract(url: URL, itemID: UUID) async -> PDFExtractedMetadata? {
        let task = await joinOrStartDownload(url: url, itemID: itemID)
        let result = await task.value
        await finishDownload(itemID: itemID, task: task)
        return result
    }

    @MainActor
    private static func joinOrStartDownload(
        url: URL,
        itemID: UUID
    ) -> Task<PDFExtractedMetadata?, Never> {
        if let existing = inFlight[itemID] { return existing }
        // Detached so the work never inherits the main actor: PDF parsing and
        // thumbnail rendering must not run on it.
        let task = Task<PDFExtractedMetadata?, Never>.detached(priority: .utility) {
            await performDownloadAndExtract(url: url, itemID: itemID)
        }
        inFlight[itemID] = task
        return task
    }

    @MainActor
    private static func finishDownload(itemID: UUID, task: Task<PDFExtractedMetadata?, Never>) {
        if inFlight[itemID] == task { inFlight[itemID] = nil }
    }

    private static func performDownloadAndExtract(url: URL, itemID: UUID) async -> PDFExtractedMetadata? {
        guard let destination = await downloadToCache(url: url, itemID: itemID) else { return nil }

        guard let document = PDFDocument(url: destination) else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }

        let attributes = document.documentAttributes
        let title = (attributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attributes?[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PDFExtractedMetadata(
            title: (title?.isEmpty == false) ? title : nil,
            author: (author?.isEmpty == false) ? author : nil,
            thumbnailData: document.page(at: 0).flatMap(thumbnailData(for:)),
            cachedFileURL: destination
        )
    }

    /// Downloads straight to a temp file and moves it into the cache, so a
    /// 100MB document never exists as a 100MB `Data` in memory. Returns the
    /// cached file's URL.
    private static func downloadToCache(url: URL, itemID: UUID) async -> URL? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/pdf,*/*", forHTTPHeaderField: "Accept")

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            // URLSession hands the file over to us; whatever happens below, the
            // temp copy must not be left behind.
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            // -1 means the server never said; the on-disk check below is the
            // one that actually holds.
            guard http.expectedContentLength <= Int64(maxBytes) else { return nil }

            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            guard let size = (attributes[.size] as? NSNumber)?.int64Value,
                  size > 0,
                  size <= Int64(maxBytes) else { return nil }

            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let destination = cacheURL(for: itemID)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            }
            return destination
        } catch {
            return nil
        }
    }

    // MARK: - Thumbnail

    private static func thumbnailData(for page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = thumbnailWidth / bounds.width
        let size = CGSize(
            width: thumbnailWidth,
            height: max(floor(bounds.height * scale), 1)
        )
        let image = page.thumbnail(of: size, for: .mediaBox)

        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpeg
        #else
        return image.jpegData(compressionQuality: 0.7)
        #endif
    }
}
