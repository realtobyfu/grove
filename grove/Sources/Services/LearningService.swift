import Foundation
import SwiftData

enum LearningError: LocalizedError {
    case emptyQuestion
    case emptyAnswer
    case unavailableCard
    case foreignContext
    case conflictingReviewEvent

    var errorDescription: String? {
        switch self {
        case .emptyQuestion: "Add a specific question before saving."
        case .emptyAnswer: "Add an answer before saving."
        case .unavailableCard: "This flashcard is no longer available."
        case .foreignContext: "This flashcard belongs to another open library."
        case .conflictingReviewEvent: "This review was already saved with a different result."
        }
    }
}

@MainActor
protocol LearningServiceProtocol {
    func preferences() -> LearningPreferences
    func dueCards(boardID: UUID?, now: Date) -> [Flashcard]
    func sessionCards(boardID: UUID?, now: Date) -> [Flashcard]
    func saveCard(_ card: Flashcard) throws
    func recordReview(
        card: Flashcard,
        rating: RecallRating,
        usedHint: Bool,
        readSource: Bool,
        sessionID: UUID,
        eventID: UUID,
        now: Date
    ) throws
    func savePreferences(_ preferences: LearningPreferences) throws
}

/// Shared by Mac, iPhone, and the intents layer. All persistence stays on the
/// main actor; asynchronous generation exchanges value snapshots separately.
@MainActor
final class LearningService: LearningServiceProtocol {
    private let modelContext: ModelContext
    private let refreshWidget: @MainActor (ModelContext) -> Void
    private(set) var lastError: String?

    init(
        modelContext: ModelContext,
        refreshWidget: @escaping @MainActor (ModelContext) -> Void = {
            LearningWidgetSnapshotStore.refresh(modelContext: $0)
        }
    ) {
        self.modelContext = modelContext
        self.refreshWidget = refreshWidget
    }

    func preferences() -> LearningPreferences {
        // Concurrent first use can produce two preference records in CloudKit.
        // Read one deterministic winner; do not delete another device's record.
        let records = (try? modelContext.fetch(FetchDescriptor<LearningPreferences>())) ?? []
        return records.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            let left = Self.preferenceKey($0)
            let right = Self.preferenceKey($1)
            return left < right
        }.first ?? LearningPreferences()
    }

    func dueCards(boardID: UUID? = nil, now: Date = .now) -> [Flashcard] {
        do {
            let cards = try modelContext.fetch(FetchDescriptor<Flashcard>())
            let reviews = try modelContext.fetch(FetchDescriptor<FlashcardReview>())
            let groups = Dictionary(grouping: reviews, by: \.cardID)
            let focus = Set(preferences().focusBoardIDs)
            var changed = false

            // Rebuild after remote imports instead of trusting a last-write-wins
            // due date from whichever device happened to export last.
            for card in cards where card.deletedAt == nil {
                let state = schedule(for: card, reviews: groups[card.id] ?? [])
                if card.dueAt != state.dueAt {
                    card.dueAt = state.dueAt
                    changed = true
                }
            }
            if changed { try modelContext.save() }
            lastError = nil

            return cards.filter { card in
                guard !card.isSuspended, card.deletedAt == nil, card.dueAt <= now else { return false }
                if let boardID { return card.boardIDs.contains(boardID) }
                return focus.isEmpty || !focus.isDisjoint(with: card.boardIDs)
            }.sorted {
                if $0.dueAt != $1.dueAt { return $0.dueAt < $1.dueAt }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func sessionCards(boardID: UUID? = nil, now: Date = .now) -> [Flashcard] {
        Array(dueCards(boardID: boardID, now: now).prefix(preferences().sessionCardLimit))
    }

    func saveCard(_ card: Flashcard) throws {
        try persistCard(card, now: .now)
    }

    /// Source snapshots stay intact when the question is rewritten. Prior
    /// reviews remain in history, but a changed question starts a new revision.
    func updateCard(
        _ card: Flashcard,
        question: String,
        answer: String,
        hints: [String],
        now: Date = .now
    ) throws {
        guard !card.isDeleted, card.deletedAt == nil else { throw LearningError.unavailableCard }
        if let context = card.modelContext, context !== modelContext { throw LearningError.foreignContext }
        try validate(question: question, answer: answer)
        card.question = question
        card.answer = answer
        card.hints = hints
        try persistCard(card, now: now)
    }

    func updateCard(
        card: Flashcard,
        question: String,
        answer: String,
        hints: [String],
        now: Date = .now
    ) throws {
        try updateCard(card, question: question, answer: answer, hints: hints, now: now)
    }

    func recordReview(
        card: Flashcard,
        rating: RecallRating,
        usedHint: Bool,
        readSource: Bool,
        sessionID: UUID,
        eventID: UUID,
        now: Date = .now
    ) throws {
        guard !card.isDeleted, !card.isSuspended, card.deletedAt == nil else { throw LearningError.unavailableCard }
        if let context = card.modelContext, context !== modelContext { throw LearningError.foreignContext }
        let reviews = try modelContext.fetch(FetchDescriptor<FlashcardReview>())

        if let previous = reviews.first(where: { $0.id == eventID }) {
            guard previous.cardID == card.id, previous.cardRevision == card.revision,
                  previous.cardFingerprint == card.revisionFingerprint,
                  previous.rating == rating, previous.usedHint == usedHint,
                  previous.readSource == readSource, previous.sessionID == sessionID else {
                throw LearningError.conflictingReviewEvent
            }
            // Preserve the original event and timestamp. A previous save may
            // have failed with that event still pending in this context.
            card.dueAt = schedule(for: card, reviews: reviews).dueAt
            try modelContext.save()
            lastError = nil
            refreshWidget(modelContext)
            return
        }

        if card.modelContext == nil { try persistCard(card, now: now) }
        let event = FlashcardReview(
            id: eventID,
            cardID: card.id,
            cardRevision: card.revision,
            rating: rating,
            usedHint: usedHint,
            readSource: readSource,
            sessionID: sessionID,
            reviewedAt: now,
            cardFingerprint: card.revisionFingerprint
        )
        modelContext.insert(event)
        card.dueAt = schedule(for: card, reviews: reviews + [event]).dueAt
        // A review does not change the content's updatedAt: it must not win a
        // content conflict simply because another device reviewed the card.
        try modelContext.save()
        lastError = nil
        refreshWidget(modelContext)
    }

    func savePreferences(_ preferences: LearningPreferences) throws {
        if let context = preferences.modelContext, context !== modelContext { throw LearningError.foreignContext }
        preferences.focusBoardIDs = Array(Set(preferences.focusBoardIDs)).sorted { $0.uuidString < $1.uuidString }
        preferences.sessionMinutes = [1, 3, 5].contains(preferences.sessionMinutes) ? preferences.sessionMinutes : 3
        preferences.updatedAt = .now
        if preferences.modelContext == nil { modelContext.insert(preferences) }
        try modelContext.save()
        lastError = nil
        refreshWidget(modelContext)
    }

    func sourceItem(for card: Flashcard) -> Item? {
        guard let id = card.sourceItemID else { return nil }
        let items: [Item] = modelContext.fetchAll()
        return items.first { $0.id == id && !$0.isDeleted }
    }

    func setSuspended(_ card: Flashcard, suspended: Bool) throws {
        guard !card.isDeleted, card.deletedAt == nil else { throw LearningError.unavailableCard }
        if let context = card.modelContext, context !== modelContext { throw LearningError.foreignContext }
        card.isSuspended = suspended
        try persistCard(card, now: .now)
    }

    func deleteCard(_ card: Flashcard, now: Date = .now) throws {
        guard !card.isDeleted else { throw LearningError.unavailableCard }
        guard let context = card.modelContext else { throw LearningError.unavailableCard }
        guard context === modelContext else { throw LearningError.foreignContext }
        card.deletedAt = now
        card.isSuspended = true
        card.updatedAt = now
        try modelContext.save()
        refreshWidget(modelContext)
    }

    private func persistCard(_ card: Flashcard, now: Date) throws {
        guard !card.isDeleted, card.deletedAt == nil else { throw LearningError.unavailableCard }
        if let context = card.modelContext, context !== modelContext { throw LearningError.foreignContext }
        try validate(question: card.question, answer: card.answer)
        let isNew = card.modelContext == nil
        card.question = card.question.trimmingCharacters(in: .whitespacesAndNewlines)
        card.answer = card.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        card.hints = card.hints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let fingerprint = Flashcard.fingerprint(question: card.question, answer: card.answer, hints: card.hints)
        if !isNew, !card.revisionFingerprint.isEmpty, card.revisionFingerprint != fingerprint {
            card.revision += 1
            card.revisionStartedAt = now
            card.dueAt = now
        }
        card.revisionFingerprint = fingerprint
        card.updatedAt = now
        if isNew { modelContext.insert(card) }
        try modelContext.save()
        lastError = nil
        refreshWidget(modelContext)
    }

    private func schedule(for card: Flashcard, reviews: [FlashcardReview]) -> LearningScheduler.State {
        let history = reviews.filter {
            $0.cardID == card.id && $0.cardRevision == card.revision
                && ($0.cardFingerprint.isEmpty || $0.cardFingerprint == card.revisionFingerprint)
        }.map {
            LearningScheduler.Review(
                id: $0.id,
                reviewedAt: $0.reviewedAt,
                rating: $0.rating,
                usedHint: $0.usedHint,
                readSource: $0.readSource
            )
        }
        let initialDueDate = card.revision == 1 ? card.createdAt : card.revisionStartedAt
        return LearningScheduler.schedule(createdAt: initialDueDate, reviews: history)
    }

    private func validate(question: String, answer: String) throws {
        if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LearningError.emptyQuestion }
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LearningError.emptyAnswer }
    }

    private static func preferenceKey(_ preferences: LearningPreferences) -> String {
        preferences.focusBoardIDs.map(\.uuidString).sorted().joined(separator: ",")
            + ":\(preferences.sessionMinutes):\(preferences.id.uuidString)"
    }
}
