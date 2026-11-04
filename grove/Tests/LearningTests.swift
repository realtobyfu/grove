import Foundation
import SQLiteData
import Testing
@testable import grove

struct LearningTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    @Test func scheduleIsIndependentOfImportOrderAndDuplicateEventRecords() {
        let events = [
            event(at: epoch, rating: .good),
            event(at: epoch.addingTimeInterval(day), rating: .good),
            event(at: epoch.addingTimeInterval(3 * day), rating: .good),
        ]
        let forward = LearningScheduler.schedule(createdAt: epoch, reviews: events)
        let imported = LearningScheduler.schedule(
            createdAt: epoch,
            reviews: [events[2], events[0], events[1], events[0]]
        )

        #expect(forward == imported)
        #expect(imported.reviewCount == 3)
        #expect(imported.dueAt == epoch.addingTimeInterval(7 * day))
    }

    @Test func supportedSuccessDoesNotReceiveAnIndependentEasyInterval() {
        let independent = LearningScheduler.schedule(
            createdAt: epoch,
            reviews: [event(at: epoch, rating: .easy)]
        )
        let supported = LearningScheduler.schedule(
            createdAt: epoch,
            reviews: [event(at: epoch, rating: .easy, usedHint: true)]
        )

        #expect(independent.dueAt == epoch.addingTimeInterval(3 * day))
        #expect(supported.dueAt == epoch.addingTimeInterval(day))
        #expect(supported.independentIntervalDays == 0)
        #expect(supported.supportedReviewCount == 1)
    }

    @Test func rapidReviewsOnTwoDevicesDoNotMultiplyTheIndependentInterval() {
        let state = LearningScheduler.schedule(
            createdAt: epoch,
            reviews: [
                event(at: epoch, rating: .good),
                event(at: epoch.addingTimeInterval(60), rating: .good),
            ]
        )

        #expect(state.reviewCount == 2)
        #expect(state.independentIntervalDays == 1)
        #expect(state.dueAt == epoch.addingTimeInterval(day + 60))
    }

    @Test func conflictingCopiesOfOneEventMergeConservatively() {
        let id = UUID()
        let earlier = event(id: id, at: epoch, rating: .easy)
        let supported = event(id: id, at: epoch.addingTimeInterval(1), rating: .good, readSource: true)
        let state = LearningScheduler.schedule(createdAt: epoch, reviews: [supported, earlier])
        let reversed = LearningScheduler.schedule(createdAt: epoch, reviews: [earlier, supported])

        #expect(state == reversed)
        #expect(state.reviewCount == 1)
        #expect(state.supportedReviewCount == 1)
        #expect(state.dueAt == epoch.addingTimeInterval(day))
    }

    @MainActor
    @Test func identicalReviewRetriesKeepOneEventAndItsOriginalDate() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        var card = Flashcard(question: "When?", answer: "After a miss.")
        card.createdAt = epoch
        try service.saveCard(card)
        let eventID = UUID()
        let sessionID = UUID()

        try service.recordReview(cardID: card.id, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch)
        try service.recordReview(cardID: card.id, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch.addingTimeInterval(30))

        let events = try reviews(in: database)
        #expect(events.count == 1)
        #expect(events.first?.reviewedAt == epoch)
        #expect(try saved(card, in: database).dueAt == epoch.addingTimeInterval(day))
    }

    /// There is no pending state any more, so the retry that matters is one whose
    /// event reached the database while the card it schedules did not.
    @MainActor
    @Test func retryOfAnEventAlreadySavedKeepsItAndStillSchedulesTheCard() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        let card = Flashcard(question: "When?", answer: "After a miss.")
        try service.saveCard(card)
        let dueBeforeReview = try saved(card, in: database).dueAt
        let eventID = UUID()
        let sessionID = UUID()
        try database.write { db in
            try FlashcardReview.insert {
                FlashcardReview(
                    id: eventID, cardID: card.id, cardRevision: card.revision, rating: .good,
                    sessionID: sessionID, reviewedAt: epoch, cardFingerprint: card.revisionFingerprint
                )
            }.execute(db)
        }
        #expect(try saved(card, in: database).dueAt == dueBeforeReview)

        try service.recordReview(cardID: card.id, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch.addingTimeInterval(30))

        let events = try reviews(in: database)
        #expect(events.count == 1)
        #expect(events.first?.reviewedAt == epoch)
        #expect(try saved(card, in: database).dueAt == epoch.addingTimeInterval(day))
    }

    @MainActor
    @Test func anEventCannotBeReusedForAnotherResult() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        let card = Flashcard(question: "When?", answer: "After a miss.")
        try service.saveCard(card)
        let eventID = UUID()
        let sessionID = UUID()
        try service.recordReview(cardID: card.id, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch)

        #expect(throws: LearningError.self) {
            try service.recordReview(cardID: card.id, rating: .easy, usedHint: false, readSource: false,
                                     sessionID: sessionID, eventID: eventID, now: epoch)
        }
        #expect(try reviews(in: database).count == 1)
    }

    @MainActor
    @Test func deletingTheSourceKeepsItsQuoteAndTitle() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        var article = Item(title: "Cache-aside", type: .article)
        article.sourceURL = "https://example.com/cache"
        let source = article
        try database.write { db in
            try Item.insert { source }.execute(db)
        }
        let card = Flashcard(question: "When?", answer: "After a miss.", sourceItem: ItemGraph(item: source),
                             sourceQuote: "Read from the store on a miss.")
        try service.saveCard(card)

        try database.write { db in
            try Item.find(source.id).delete().execute(db)
        }

        let kept = try saved(card, in: database)
        #expect(kept.sourceQuote == "Read from the store on a miss.")
        #expect(kept.sourceTitle == "Cache-aside")
        #expect(kept.sourceURL == "https://example.com/cache")
        #expect(service.sourceItem(for: kept) == nil)
    }

    @MainActor
    @Test func rewritingAQuestionRetainsHistoryButStartsFreshScheduling() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        var card = Flashcard(question: "Old question?", answer: "Old answer.")
        card.createdAt = epoch
        try service.saveCard(card)
        try service.recordReview(cardID: card.id, rating: .easy, usedHint: false, readSource: false,
                                 sessionID: UUID(), eventID: UUID(), now: epoch)
        let editDate = epoch.addingTimeInterval(day)

        try service.updateCard(card.id, question: "A more precise question?", answer: "A better answer.",
                               hints: [], now: editDate)
        let due = service.dueCards(now: editDate)

        let rewritten = try saved(card, in: database)
        #expect(rewritten.revision == 2)
        #expect(due.contains { $0.id == card.id })
        #expect(rewritten.dueAt == editDate)
        #expect(try reviews(in: database).count == 1)
    }

    @MainActor
    @Test func focusAndSessionBudgetFilterTheQueueWithoutASecondDeckHierarchy() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        let chosen = UUID()
        let other = UUID()
        for index in 0..<4 {
            var card = Flashcard(question: "Question \(index)?", answer: "Answer.")
            card.createdAt = epoch
            card.boardIDs = [chosen]
            try service.saveCard(card)
        }
        var otherCard = Flashcard(question: "Other board?", answer: "Answer.")
        otherCard.createdAt = epoch
        otherCard.boardIDs = [other]
        try service.saveCard(otherCard)
        let preferences = LearningPreferences(focusBoardIDs: [chosen], sessionMinutes: 1)
        try service.savePreferences(preferences)

        #expect(service.dueCards(now: epoch.addingTimeInterval(day)).count == 4)
        #expect(service.sessionCards(now: epoch.addingTimeInterval(day)).count == 2)
        #expect(service.dueCards(boardID: other, now: epoch.addingTimeInterval(day)).map(\.id) == [otherCard.id])
    }

    @MainActor
    @Test func concurrentContentForkDoesNotSupplyEvidenceForTheWinningQuestion() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        var card = Flashcard(question: "Which copy changes?", answer: "The original copy.")
        card.createdAt = epoch
        try service.saveCard(card)
        let imported = FlashcardReview(
            cardID: card.id,
            cardRevision: card.revision,
            rating: .easy,
            sessionID: UUID(),
            reviewedAt: epoch,
            cardFingerprint: Flashcard.fingerprint(question: "A different question?", answer: "Different.", hints: [])
        )
        try database.write { db in
            try FlashcardReview.insert { imported }.execute(db)
        }

        let due = service.dueCards(now: epoch.addingTimeInterval(1))

        #expect(due.contains { $0.id == card.id })
        #expect(try saved(card, in: database).dueAt == epoch)
    }

    @MainActor
    @Test func suspendingOrSavingUnchangedDoesNotPostponeARewrittenQuestion() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        var card = Flashcard(question: "Old?", answer: "Old.")
        card.createdAt = epoch
        try service.saveCard(card)
        let editDate = epoch.addingTimeInterval(day)
        try service.updateCard(card.id, question: "New?", answer: "New.", hints: [], now: editDate)

        try service.setSuspended(card.id, suspended: true)
        try service.setSuspended(card.id, suspended: false)
        try service.saveCard(try saved(card, in: database))

        let rewritten = try saved(card, in: database)
        #expect(rewritten.revision == 2)
        #expect(rewritten.revisionStartedAt == editDate)
        #expect(service.dueCards(now: editDate).map(\.id) == [card.id])
        #expect(try saved(card, in: database).dueAt == editDate)
    }

    /// `LearningError.foreignContext` is gone: cards are reached by ID now, so a
    /// library that doesn't hold the card simply can't find it.
    @MainActor
    @Test func operationsOnAnotherLibrarysCardFailWithoutTouchingEitherLibrary() throws {
        let owning = try AppDatabase.openInMemory()
        let other = try AppDatabase.openInMemory()
        let card = Flashcard(question: "Original?", answer: "Original.")
        try LearningService(database: owning, refreshWidget: { _ in }).saveCard(card)
        let foreign = LearningService(database: other, refreshWidget: { _ in })

        #expect(throws: LearningError.unavailableCard) {
            try foreign.updateCard(card.id, question: "Replaced?", answer: "Changed.", hints: [])
        }
        #expect(try saved(card, in: owning).question == "Original?")
        #expect(throws: LearningError.unavailableCard) {
            try foreign.deleteCard(card.id)
        }
        let untouched = try saved(card, in: owning)
        #expect(untouched.deletedAt == nil)
        #expect(!untouched.isSuspended)
        #expect(try other.read { try Flashcard.all.fetchCount($0) } == 0)
    }

    @MainActor
    @Test func suspendedAndDeletedCardsStayOutOfReviewWithoutErasingEvents() throws {
        let database = try AppDatabase.openInMemory()
        let service = LearningService(database: database, refreshWidget: { _ in })
        var card = Flashcard(question: "Which copy?", answer: "The original.")
        card.createdAt = epoch
        try service.saveCard(card)
        try service.recordReview(cardID: card.id, rating: .again, usedHint: false, readSource: false,
                                 sessionID: UUID(), eventID: UUID(), now: epoch)
        try service.setSuspended(card.id, suspended: true)
        #expect(service.dueCards(now: epoch.addingTimeInterval(day)).isEmpty)
        try service.setSuspended(card.id, suspended: false)
        try service.deleteCard(card.id, now: epoch.addingTimeInterval(day))

        #expect(service.dueCards(now: epoch.addingTimeInterval(2 * day)).isEmpty)
        #expect(try reviews(in: database).count == 1)
        #expect(try database.read { try Flashcard.all.fetchCount($0) } == 1)
    }

    @MainActor
    @Test func draftRejectsAnInventedSupportingQuote() {
        let response = #"{"question":"When?","answer":"After a miss.","hints":["Think about absence."],"supportingQuote":"A fabricated citation"}"#
        #expect(FlashcardDraftService.parse(response, sourceQuote: "Read from the store on a miss.") == nil)
    }

    @MainActor
    @Test func groundedDraftKeepsOnlyShortNonAnswerHints() throws {
        let response = #"{"question":"When?","answer":"After a miss.","hints":["Think about absence.","After a miss.","Consider the next request."],"supportingQuote":"on a miss"}"#
        let draft = try #require(FlashcardDraftService.parse(response, sourceQuote: "Read from the store on a miss."))
        #expect(draft.hints == ["Think about absence.", "Consider the next request."])
        #expect(draft.sourceQuote == "on a miss")
    }

    private func event(
        id: UUID = UUID(),
        at date: Date,
        rating: RecallRating,
        usedHint: Bool = false,
        readSource: Bool = false
    ) -> LearningScheduler.Review {
        LearningScheduler.Review(id: id, reviewedAt: date, rating: rating, usedHint: usedHint, readSource: readSource)
    }

    /// The card as stored. Rows are values, so the one a test built never changes.
    private func saved(_ card: Flashcard, in database: any DatabaseWriter) throws -> Flashcard {
        try #require(try database.read { try Flashcard.find(card.id).fetchOne($0) })
    }

    private func reviews(in database: any DatabaseWriter) throws -> [FlashcardReview] {
        try database.read { try FlashcardReview.all.fetchAll($0) }
    }
}
