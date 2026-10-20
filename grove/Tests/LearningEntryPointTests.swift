import Foundation
import Testing
@testable import grove

@MainActor
struct LearningEntryPointTests {
    @Test func widgetRouteKeepsBoardAndContainsNoLearningText() throws {
        let boardID = UUID()
        let snapshot = LearningWidgetSnapshot(sessionMinutes: 3, hasCards: true, boardID: boardID, updatedAt: .now)
        let router = LearningLaunchCoordinator()
        #expect(router.handle(snapshot.reviewURL))
        #expect(router.review?.boardID == boardID)
        let keys = try #require(URLComponents(url: snapshot.reviewURL, resolvingAgainstBaseURL: false)?.queryItems).map(\.name)
        #expect(keys == ["board"])
    }

    @Test func malformedRouteDoesNotPresentReview() {
        for raw in ["https://review", "grove://review/extra", "grove://review?board", "grove://review?board=invalid"] {
            let router = LearningLaunchCoordinator()
            #expect(!router.handle(URL(string: raw)!))
            #expect(router.review == nil)
        }
    }

    @Test func repeatedSystemEntryDoesNotReplaceActiveSession() throws {
        let router = LearningLaunchCoordinator()
        router.openReview()
        let firstID = try #require(router.review?.id)
        router.openReview(boardID: UUID())
        #expect(router.review?.id == firstID)
        #expect(router.review?.boardID == nil)
    }
}
