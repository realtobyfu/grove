import Foundation
@testable import grove

/// Mock image download service for testing. Returns canned data or nil.
final class MockImageDownloadService: ImageDownloadServiceProtocol, @unchecked Sendable {
    var result: Data?
    var downloadedURLs: [String] = []

    func downloadAndCompress(urlString: String) async -> Data? {
        downloadedURLs.append(urlString)
        return result
    }

    func compressImageData(_ data: Data) -> Data? {
        return data
    }
}
