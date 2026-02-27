import Foundation

/// Helper to create grove:// deep link URLs for drag-and-drop support on iPad.
extension Item {
    /// Deep link URL for this item, usable as a drag-and-drop payload.
    var dragURL: URL {
        if let urlString = sourceURL, let url = URL(string: urlString) {
            return url
        }
        return URL(string: "grove://item/\(id.uuidString)")!
    }
}
