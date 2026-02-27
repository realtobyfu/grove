import SwiftUI
import Foundation

/// Parses grove:// deep links and provides navigation state for iOS views.
///
/// Supported schemes:
///   - grove://item/{uuid}       → navigate to item reader
///   - grove://board/{uuid}      → navigate to board in Library
///   - grove://chat/{uuid}       → navigate to conversation in Chat
///   - grove://capture?url={enc} → trigger capture sheet with pre-filled URL
///   - grove://search?q={query}  → open search with query
@Observable
final class DeepLinkRouter {

    // MARK: - Navigation state

    /// The tab to select after routing.
    var selectedTab: TabRootView.Tab?

    /// UUID of an item to navigate to after selecting its tab.
    var pendingItemID: UUID?

    /// UUID of a board to navigate to.
    var pendingBoardID: UUID?

    /// UUID of a conversation to navigate to.
    var pendingConversationID: UUID?

    /// URL to pre-fill in the capture sheet.
    var pendingCaptureURL: String?

    /// Query to pre-fill in search.
    var pendingSearchQuery: String?

    // MARK: - Routing

    /// Parse a grove:// URL and update navigation state accordingly.
    /// Returns true if the URL was handled.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "grove" else { return false }
        let host = url.host(percentEncoded: false) ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "item":
            guard let uuidString = pathComponents.first,
                  let uuid = UUID(uuidString: uuidString) else { return false }
            pendingItemID = uuid
            selectedTab = .home
            return true

        case "board":
            guard let uuidString = pathComponents.first,
                  let uuid = UUID(uuidString: uuidString) else { return false }
            pendingBoardID = uuid
            selectedTab = .library
            return true

        case "chat":
            guard let uuidString = pathComponents.first,
                  let uuid = UUID(uuidString: uuidString) else { return false }
            pendingConversationID = uuid
            selectedTab = .chat
            return true

        case "capture":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            pendingCaptureURL = components?.queryItems?.first(where: { $0.name == "url" })?.value
            selectedTab = .home
            return true

        case "search":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            pendingSearchQuery = components?.queryItems?.first(where: { $0.name == "q" })?.value
            selectedTab = .library
            return true

        default:
            return false
        }
    }

    /// Clear pending navigation after it has been consumed by a view.
    func clearPendingItem() { pendingItemID = nil }
    func clearPendingBoard() { pendingBoardID = nil }
    func clearPendingConversation() { pendingConversationID = nil }
    func clearPendingCapture() { pendingCaptureURL = nil }
    func clearPendingSearch() { pendingSearchQuery = nil }
}
