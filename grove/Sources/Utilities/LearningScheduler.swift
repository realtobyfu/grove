import Foundation

/// A conservative recall scheduler, deliberately independent of item-opening
/// engagement. This is not FSRS: preserving the event log allows that scheduler
/// to be evaluated later without losing the user's learning history.
enum LearningScheduler {
    struct Review: Sendable {
        let id: UUID
        let reviewedAt: Date
        let rating: RecallRating
        let usedHint: Bool
        let readSource: Bool

        var usedSupport: Bool { usedHint || readSource }
    }

    struct State: Equatable, Sendable {
        var dueAt: Date
        var independentIntervalDays: Double = 0
        var reviewCount: Int = 0
        var supportedReviewCount: Int = 0
    }

    static func schedule(createdAt: Date, reviews: [Review]) -> State {
        var state = State(dueAt: createdAt)
        var lastIndependentSuccess: Date?

        for review in canonicalReviews(reviews) {
            state.reviewCount += 1
            if review.usedSupport { state.supportedReviewCount += 1 }

            if review.rating == .again {
                state.independentIntervalDays = 0
                lastIndependentSuccess = nil
                state.dueAt = review.reviewedAt.addingTimeInterval(10 * 60)
                continue
            }

            if review.usedSupport {
                // A useful supported practice is not evidence that a long
                // independent recall interval can safely grow.
                state.independentIntervalDays = min(state.independentIntervalDays, 1)
                lastIndependentSuccess = nil
                state.dueAt = review.reviewedAt.addingTimeInterval(24 * 60 * 60)
                continue
            }

            let previous = state.independentIntervalDays
            let mayGrow = lastIndependentSuccess.map {
                review.reviewedAt.timeIntervalSince($0) >= 24 * 60 * 60
            } ?? true
            switch review.rating {
            case .again:
                break // Handled above.
            case .hard:
                state.independentIntervalDays = max(1, previous / 2)
            case .good:
                state.independentIntervalDays = lastIndependentSuccess == nil
                    ? 1 : (mayGrow ? min(120, max(1, previous * 2)) : max(1, previous))
            case .easy:
                state.independentIntervalDays = lastIndependentSuccess == nil
                    ? 3 : (mayGrow ? min(120, max(3, previous * 3)) : max(1, previous))
            }
            lastIndependentSuccess = review.reviewedAt
            state.dueAt = review.reviewedAt.addingTimeInterval(state.independentIntervalDays * 24 * 60 * 60)
        }
        return state
    }

    /// CloudKit may deliver the same logical review in more than one record.
    /// Merge conflicting copies conservatively and sort ties by event ID, so
    /// importing records in a different order cannot change the next due date.
    static func canonicalReviews(_ reviews: [Review]) -> [Review] {
        var events: [UUID: Review] = [:]
        for review in reviews {
            guard let previous = events[review.id] else {
                events[review.id] = review
                continue
            }
            events[review.id] = Review(
                id: review.id,
                reviewedAt: min(previous.reviewedAt, review.reviewedAt),
                rating: previous.rating.order <= review.rating.order ? previous.rating : review.rating,
                usedHint: previous.usedHint || review.usedHint,
                readSource: previous.readSource || review.readSource
            )
        }
        return events.values.sorted {
            if $0.reviewedAt != $1.reviewedAt { return $0.reviewedAt < $1.reviewedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
