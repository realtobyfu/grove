import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
            return compressImageData(data)
        } catch {
            return nil
        }
    }

    /// Compress raw image data (e.g. from LPMetadataProvider) using the same resize/JPEG pipeline.
    func compressImageData(_ data: Data) -> Data? {
        let maxWidth: CGFloat = 600
        let maxHeight: CGFloat = 315

        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

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

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpegData
        #else
        guard let image = UIImage(data: data) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

        var targetSize = originalSize
        if originalSize.width > maxWidth || originalSize.height > maxHeight {
            let widthRatio = maxWidth / originalSize.width
            let heightRatio = maxHeight / originalSize.height
            let scale = min(widthRatio, heightRatio)
            targetSize = CGSize(
                width: floor(originalSize.width * scale),
                height: floor(originalSize.height * scale)
            )
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedData = renderer.jpegData(withCompressionQuality: 0.7) { context in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedData
        #endif
    }
}
