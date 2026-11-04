import Foundation
import SQLiteData

enum LearningError: LocalizedError {
    case emptyQuestion
    case emptyAnswer
    case unavailableCard
    case conflictingReviewEvent

    var errorDescription: String? {
        switch self {
        case .emptyQuestion: "Add a specific question before saving."
        case .emptyAnswer: "Add an answer before saving."
        case .unavailableCard: "This flashcard is no longer available."
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
        cardID: Flashcard.ID,
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
    private let database: any DatabaseWriter
    private let refreshWidget: @MainActor (any DatabaseWriter) -> Void
    private(set) var lastError: String?

    init(
        database: any DatabaseWriter = AppDatabase.current,
        refreshWidget: @escaping @MainActor (any DatabaseWriter) -> Void = {
            LearningWidgetSnapshotStore.refresh(database: $0)
        }
    ) {
        self.database = database
        self.refreshWidget = refreshWidget
    }

    func preferences() -> LearningPreferences {
        // Reading never creates the row. Until someone saves, these are the defaults.
        let stored = database.attemptRead { db in
            try LearningPreferences.find(LearningPreferences.sharedID).fetchOne(db)
        }
        return (stored ?? nil) ?? LearningPreferences()
    }

    func dueCards(boardID: UUID? = nil, now: Date = .now) -> [Flashcard] {
        do {
            let (stored, reviews) = try database.read { db in
                (try Flashcard.all.fetchAll(db), try FlashcardReview.all.fetchAll(db))
            }
            var cards = stored
            let groups = Dictionary(grouping: reviews, by: \.cardID)
            let focus = Set(preferences().focusBoardIDs)
            var rescheduled: [Flashcard.ID: Date] = [:]

            // Rebuild after remote imports instead of trusting a last-write-wins
            // due date from whichever device happened to export last.
            for index in cards.indices where cards[index].deletedAt == nil {
                let state = schedule(for: cards[index], reviews: groups[cards[index].id] ?? [])
                if !Self.isSameDueDate(cards[index].dueAt, state.dueAt) {
                    cards[index].dueAt = state.dueAt
                    rescheduled[cards[index].id] = state.dueAt
                }
            }
            if !rescheduled.isEmpty {
                try database.write { db in
                    for (id, dueAt) in rescheduled {
                        try Flashcard.modify(id, in: db) { $0.dueAt = dueAt }
                    }
                }
            }
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

    /// Inserts a new card, or saves a caller's edits to an existing one. The
    /// passed value counts as the edit, so pass a current copy: stale content
    /// here reads as a rewrite and starts a new revision.
    func saveCard(_ card: Flashcard) throws {
        let now = Date.now
        try database.write { db in
            guard try Flashcard.find(card.id).fetchOne(db) != nil else {
                var newCard = card
                try prepareForSaving(&newCard, isNew: true, now: now)
                try Flashcard.insert { newCard }.execute(db)
                return
            }
            try persistCard(card.id, now: now, in: db) { $0.applyEdits(from: card) }
        }
        lastError = nil
        refreshWidget(database)
    }

    /// Source snapshots stay intact when the question is rewritten. Prior
    /// reviews remain in history, but a changed question starts a new revision.
    func updateCard(
        _ cardID: Flashcard.ID,
        question: String,
        answer: String,
        hints: [String],
        now: Date = .now
    ) throws {
        try database.write { db in
            try persistCard(cardID, now: now, in: db) { card in
                card.question = question
                card.answer = answer
                card.hints = hints
            }
        }
        lastError = nil
        refreshWidget(database)
    }

    func updateCard(
        card: Flashcard,
        question: String,
        answer: String,
        hints: [String],
        now: Date = .now
    ) throws {
        try updateCard(card.id, question: question, answer: answer, hints: hints, now: now)
    }

    func recordReview(
        cardID: Flashcard.ID,
        rating: RecallRating,
        usedHint: Bool,
        readSource: Bool,
        sessionID: UUID,
        eventID: UUID,
        now: Date = .now
    ) throws {
        try database.write { db in
            guard let card = try Flashcard.find(cardID).fetchOne(db),
                  !card.isSuspended, card.deletedAt == nil else { throw LearningError.unavailableCard }
            let reviews = try FlashcardReview.where { $0.cardID.eq(cardID) }.fetchAll(db)

            // By ID alone, not among this card's reviews: an event already saved
            // for another card is a conflict too, and the primary key would
            // otherwise reject it with a database error.
            if let previous = try FlashcardReview.find(eventID).fetchOne(db) {
                guard previous.cardID == card.id, previous.cardRevision == card.revision,
                      previous.cardFingerprint == card.revisionFingerprint,
                      previous.rating == rating, previous.usedHint == usedHint,
                      previous.readSource == readSource, previous.sessionID == sessionID else {
                    throw LearningError.conflictingReviewEvent
                }
                // Preserve the original event and timestamp. The caller may be
                // retrying after a write it never saw finish.
                let dueAt = schedule(for: card, reviews: reviews).dueAt
                try Flashcard.modify(card.id, in: db) { $0.dueAt = dueAt }
                return
            }

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
            try FlashcardReview.insert { event }.execute(db)
            let dueAt = schedule(for: card, reviews: reviews + [event]).dueAt
            // A review does not change the content's updatedAt: it must not win a
            // content conflict simply because another device reviewed the card.
            try Flashcard.modify(card.id, in: db) { $0.dueAt = dueAt }
        }
        lastError = nil
        refreshWidget(database)
    }

    func savePreferences(_ preferences: LearningPreferences) throws {
        var row = preferences
        row.focusBoardIDs = Array(Set(row.focusBoardIDs)).sorted { $0.uuidString < $1.uuidString }
        row.sessionMinutes = [1, 3, 5].contains(row.sessionMinutes) ? row.sessionMinutes : 3
        row.updatedAt = .now
        try database.write { db in
            try LearningPreferences.upsert { row }.execute(db)
        }
        lastError = nil
        refreshWidget(database)
    }

    func sourceItem(for card: Flashcard) -> Item? {
        guard let id = card.sourceItemID else { return nil }
        return database.attemptRead { db in try Item.find(id).fetchOne(db) } ?? nil
    }

    func setSuspended(_ cardID: Flashcard.ID, suspended: Bool) throws {
        try database.write { db in
            try persistCard(cardID, now: .now, in: db) { $0.isSuspended = suspended }
        }
        lastError = nil
        refreshWidget(database)
    }

    func deleteCard(_ cardID: Flashcard.ID, now: Date = .now) throws {
        try database.write { db in
            let deleted = try Flashcard.modify(cardID, in: db) { card in
                card.deletedAt = now
                card.isSuspended = true
                card.updatedAt = now
            }
            guard deleted != nil else { throw LearningError.unavailableCard }
        }
        refreshWidget(database)
    }

    /// Applies `edit` to the card as it stands in the database, not to any copy
    /// a caller held, and stores the result.
    private func persistCard(
        _ cardID: Flashcard.ID,
        now: Date,
        in db: Database,
        edit: (inout Flashcard) -> Void
    ) throws {
        let saved = try Flashcard.modify(cardID, in: db) { card in
            edit(&card)
            try prepareForSaving(&card, isNew: false, now: now)
        }
        guard saved != nil else { throw LearningError.unavailableCard }
    }

    /// Validates and tidies a card about to be stored, and starts a new revision
    /// if its content changed.
    private func prepareForSaving(_ card: inout Flashcard, isNew: Bool, now: Date) throws {
        guard card.deletedAt == nil else { throw LearningError.unavailableCard }
        try validate(question: card.question, answer: card.answer)
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

    /// SQLite keeps a date to the millisecond. A long run of hard and easy ratings
    /// can leave an interval that isn't a whole number of milliseconds, and the
    /// stored due date then never equals the computed one, so an exact check
    /// would rewrite, and re-sync, that card on every read.
    private static func isSameDueDate(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.002
    }
}

private extension Flashcard {
    /// What saving a held copy may change. The schedule, revision and deletion
    /// stay as stored, so a copy older than the row can't roll them back.
    mutating func applyEdits(from card: Flashcard) {
        question = card.question
        answer = card.answer
        hints = card.hints
        sourceItemID = card.sourceItemID
        sourceReflectionID = card.sourceReflectionID
        sourceTitle = card.sourceTitle
        sourceQuote = card.sourceQuote
        sourceURL = card.sourceURL
        sourceLocator = card.sourceLocator
        boardIDs = card.boardIDs
        isSuspended = card.isSuspended
    }
}
