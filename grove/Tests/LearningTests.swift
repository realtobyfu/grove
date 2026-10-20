import Foundation
import SwiftData
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
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "When?", answer: "After a miss.")
        card.createdAt = epoch
        try service.saveCard(card)
        let eventID = UUID()
        let sessionID = UUID()

        try service.recordReview(card: card, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch)
        try service.recordReview(card: card, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch.addingTimeInterval(30))

        let events = try context.fetch(FetchDescriptor<FlashcardReview>())
        #expect(events.count == 1)
        #expect(events.first?.reviewedAt == epoch)
        #expect(card.dueAt == epoch.addingTimeInterval(day))
    }

    @MainActor
    @Test func retryCommitsAnEventThatWasStillPendingAfterAnEarlierSaveFailure() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "When?", answer: "After a miss.")
        try service.saveCard(card)
        let eventID = UUID()
        let sessionID = UUID()
        // A failed save leaves an inserted event pending in the model context.
        context.insert(FlashcardReview(
            id: eventID, cardID: card.id, cardRevision: card.revision, rating: .good,
            sessionID: sessionID, reviewedAt: epoch, cardFingerprint: card.revisionFingerprint
        ))

        try service.recordReview(card: card, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch.addingTimeInterval(30))

        let reloaded = ModelContext(context.container)
        let saved = try reloaded.fetch(FetchDescriptor<FlashcardReview>())
        #expect(saved.count == 1)
        #expect(saved.first?.reviewedAt == epoch)
        #expect(card.dueAt == epoch.addingTimeInterval(day))
    }

    @MainActor
    @Test func anEventCannotBeReusedForAnotherResult() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "When?", answer: "After a miss.")
        try service.saveCard(card)
        let eventID = UUID()
        let sessionID = UUID()
        try service.recordReview(card: card, rating: .good, usedHint: false, readSource: false,
                                 sessionID: sessionID, eventID: eventID, now: epoch)

        #expect(throws: LearningError.self) {
            try service.recordReview(card: card, rating: .easy, usedHint: false, readSource: false,
                                     sessionID: sessionID, eventID: eventID, now: epoch)
        }
        #expect(try context.fetch(FetchDescriptor<FlashcardReview>()).count == 1)
    }

    @MainActor
    @Test func deletingTheSourceKeepsItsQuoteAndTitle() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let article = Item(title: "Cache-aside", type: .article)
        article.sourceURL = "https://example.com/cache"
        context.insert(article)
        let card = Flashcard(question: "When?", answer: "After a miss.", sourceItem: article,
                             sourceQuote: "Read from the store on a miss.")
        try service.saveCard(card)

        context.delete(article)
        try context.save()

        #expect(card.sourceQuote == "Read from the store on a miss.")
        #expect(card.sourceTitle == "Cache-aside")
        #expect(card.sourceURL == "https://example.com/cache")
        #expect(service.sourceItem(for: card) == nil)
    }

    @MainActor
    @Test func rewritingAQuestionRetainsHistoryButStartsFreshScheduling() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "Old question?", answer: "Old answer.")
        card.createdAt = epoch
        try service.saveCard(card)
        try service.recordReview(card: card, rating: .easy, usedHint: false, readSource: false,
                                 sessionID: UUID(), eventID: UUID(), now: epoch)
        let editDate = epoch.addingTimeInterval(day)

        try service.updateCard(card, question: "A more precise question?", answer: "A better answer.",
                               hints: [], now: editDate)
        let due = service.dueCards(now: editDate)

        #expect(card.revision == 2)
        #expect(due.contains { $0.id == card.id })
        #expect(card.dueAt == editDate)
        #expect(try context.fetch(FetchDescriptor<FlashcardReview>()).count == 1)
    }

    @MainActor
    @Test func focusAndSessionBudgetFilterTheQueueWithoutASecondDeckHierarchy() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let chosen = UUID()
        let other = UUID()
        for index in 0..<4 {
            let card = Flashcard(question: "Question \(index)?", answer: "Answer.")
            card.createdAt = epoch
            card.boardIDs = [chosen]
            try service.saveCard(card)
        }
        let otherCard = Flashcard(question: "Other board?", answer: "Answer.")
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
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "Which copy changes?", answer: "The original copy.")
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
        context.insert(imported)
        try context.save()

        let due = service.dueCards(now: epoch.addingTimeInterval(1))

        #expect(due.contains { $0.id == card.id })
        #expect(card.dueAt == epoch)
    }

    @MainActor
    @Test func suspendingOrSavingUnchangedDoesNotPostponeARewrittenQuestion() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "Old?", answer: "Old.")
        card.createdAt = epoch
        try service.saveCard(card)
        let editDate = epoch.addingTimeInterval(day)
        try service.updateCard(card, question: "New?", answer: "New.", hints: [], now: editDate)

        try service.setSuspended(card, suspended: true)
        try service.setSuspended(card, suspended: false)
        try service.saveCard(card)

        #expect(card.revision == 2)
        #expect(card.revisionStartedAt == editDate)
        #expect(service.dueCards(now: editDate).map(\.id) == [card.id])
        #expect(card.dueAt == editDate)
    }

    @MainActor
    @Test func foreignContextOperationsFailBeforeMutatingTheOtherLibrary() throws {
        let owning = try makeContext()
        let other = try makeContext()
        let card = Flashcard(question: "Original?", answer: "Original.")
        try LearningService(modelContext: owning, refreshWidget: { _ in }).saveCard(card)
        let foreign = LearningService(modelContext: other, refreshWidget: { _ in })

        #expect(throws: LearningError.self) {
            try foreign.updateCard(card, question: "Replaced?", answer: "Changed.", hints: [])
        }
        #expect(card.question == "Original?")
        #expect(throws: LearningError.self) {
            try foreign.deleteCard(card)
        }
        #expect(card.deletedAt == nil)
        #expect(!card.isSuspended)
    }

    @MainActor
    @Test func suspendedAndDeletedCardsStayOutOfReviewWithoutErasingEvents() throws {
        let context = try makeContext()
        let service = LearningService(modelContext: context, refreshWidget: { _ in })
        let card = Flashcard(question: "Which copy?", answer: "The original.")
        card.createdAt = epoch
        try service.saveCard(card)
        try service.recordReview(card: card, rating: .again, usedHint: false, readSource: false,
                                 sessionID: UUID(), eventID: UUID(), now: epoch)
        try service.setSuspended(card, suspended: true)
        #expect(service.dueCards(now: epoch.addingTimeInterval(day)).isEmpty)
        try service.setSuspended(card, suspended: false)
        try service.deleteCard(card, now: epoch.addingTimeInterval(day))

        #expect(service.dueCards(now: epoch.addingTimeInterval(2 * day)).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FlashcardReview>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Flashcard>()).count == 1)
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

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration("LearningTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
