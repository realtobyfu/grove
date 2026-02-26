import Foundation
import AppKit

protocol ImageDownloadServiceProtocol: Sendable {
    func downloadAndCompress(urlString: String) async -> Data?
    func compressImageData(_ data: Data) -> Data?
}

/// Downloads OG images from URLs, resizes to fit 600×315 max, and compresses to JPEG.
final class ImageDownloadService: ImageDownloadServiceProtocol, Sendable {

    static let shared = ImageDownloadService()

    private init() {}

    /// Download an image URL, resize to fit within 600×315 (never upscales), and compress to JPEG 0.7.
    /// Returns nil on any failure.
    func downloadAndCompress(urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            guard let nsImage = NSImage(data: data) else { return nil }
            return compressImage(nsImage)
        } catch {
            return nil
        }
    }

    /// Compress raw image data (e.g. from LPMetadataProvider) using the same resize/JPEG pipeline.
    func compressImageData(_ data: Data) -> Data? {
        guard let nsImage = NSImage(data: data) else { return nil }
        return compressImage(nsImage)
    }

    private func compressImage(_ image: NSImage) -> Data? {
        let maxWidth: CGFloat = 600
        let maxHeight: CGFloat = 315
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

        // Calculate target size — fit within max bounds, never upscale
        var targetSize = originalSize
        if originalSize.width > maxWidth || originalSize.height > maxHeight {
            let widthRatio = maxWidth / originalSize.width
            let heightRatio = maxHeight / originalSize.height
            let scale = min(widthRatio, heightRatio)
            targetSize = NSSize(
                width: floor(originalSize.width * scale),
                height: floor(originalSize.height * scale)
            )
        }

        // Draw resized image
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        // Convert to JPEG via tiffRepresentation → NSBitmapImageRep
        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpegData
    }
}
