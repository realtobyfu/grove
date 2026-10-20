import Foundation
import Observation

struct LearningReviewRoute: Identifiable {
    let id = UUID()
    var boardID: UUID?
}

/// Holds system entry points until a scene is ready, including cold launches.
@MainActor
@Observable
final class LearningLaunchCoordinator {
    static let shared = LearningLaunchCoordinator()
    var review: LearningReviewRoute?

    func openReview(boardID: UUID? = nil) {
        guard review == nil else { return }
        review = LearningReviewRoute(boardID: boardID)
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "grove", url.host == "review",
              url.pathComponents.filter({ $0 != "/" }).isEmpty else { return false }
        let parameter = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "board" }
        if let parameter {
            guard let value = parameter.value, let boardID = UUID(uuidString: value) else { return false }
            openReview(boardID: boardID)
        } else {
            openReview()
        }
        return true
    }
}
