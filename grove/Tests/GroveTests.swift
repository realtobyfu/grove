import Foundation
import SQLiteData
import Testing
@testable import grove

private final class FocusEventRecorder: @unchecked Sendable {
    var events: [Notification.Name] = []
}

struct GroveTests {
    @MainActor
    @Test func globalCaptureRemainsInInboxWithoutAUserSelectedBoard() throws {
        let database = try AppDatabase.openInMemory()
        let service = CaptureService(database: database)

        let item = service.captureItem(input: "Unfiled thought")

        let saved = try #require(try database.read { try Item.find(item.id).fetchOne($0) })
        #expect(saved.status == .inbox)
        #expect(saved.boardID == nil)
    }

    @MainActor
    @Test func boardTargetedCaptureIsImmediatelyActive() throws {
        let database = try AppDatabase.openInMemory()
        let board = Board(title: "Research")
        try database.write { db in
            try Board.insert { board }.execute(db)
        }
        let service = CaptureService(database: database)

        let item = service.captureItem(input: "Filed thought", board: board)

        let saved = try #require(try database.read { try Item.find(item.id).fetchOne($0) })
        #expect(saved.status == .active)
        #expect(saved.boardID == board.id)
    }

    @MainActor
    @Test func explicitBoardAssignmentApprovesInboxItemWithoutDuplicatingBoard() throws {
        let database = try AppDatabase.openInMemory()
        var item = Item(title: "Pending", type: .note)
        item.status = .inbox
        let board = Board(title: "Research")
        try database.write { db in
            try Item.insert { item }.execute(db)
            try Board.insert { board }.execute(db)
        }
        let viewModel = ItemViewModel(database: database)

        viewModel.assignToBoard(item.id, board: board)
        viewModel.assignToBoard(item.id, board: board)

        let library = try database.read { try Library.fetch($0) }
        let saved = try #require(library.item(item.id))
        #expect(saved.status == .active)
        #expect(saved.board?.id == board.id)
        #expect(library.board(board.id)?.items.map(\.id) == [item.id])
    }

    @MainActor
    @Test func movingInboxItemsToBoardApprovesThem() throws {
        let database = try AppDatabase.openInMemory()
        var item = Item(title: "Pending", type: .note)
        item.status = .inbox
        let board = Board(title: "Research")
        try database.write { db in
            try Item.insert { item }.execute(db)
            try Board.insert { board }.execute(db)
        }
        let viewModel = ItemViewModel(database: database)

        viewModel.moveItemsToBoard([item.id], board: board)

        let saved = try #require(try database.read { try Item.find(item.id).fetchOne($0) })
        #expect(saved.status == .active)
        #expect(saved.boardID == board.id)
    }

    @MainActor
    @Test func boardSuggestionSelectionRecordsLocalEvaluationSignal() {
        var item = Item(title: "Pending", type: .note)
        let board = Board(title: "Research")
        let decision = BoardSuggestionDecision(
            suggestedName: board.title,
            mode: .existing,
            recommendedBoardID: board.id,
            confidence: 0.91,
            reason: "Strong title match",
            alternativeBoardIDs: []
        )
        BoardSuggestionMetadata.apply(decision, to: &item)

        BoardSuggestionMetadata.recordSelection(board, on: &item)

        #expect(item.metadata["pendingBoardSuggestion"] == nil)
        #expect(item.metadata["boardSuggestionOutcome"] == "selected")
        #expect(item.metadata["boardSuggestionSelectedBoardID"] == board.id.uuidString)
        #expect(item.metadata["boardSuggestionMatchedRecommendation"] == "true")
    }

    @MainActor
    @Test func entitlementServiceDefaultsToFreeTier() {
        let defaults = testDefaults()
        let service = EntitlementService(defaults: defaults)

        #expect(service.tier == .free)
        #expect(!service.hasAccess(to: .sync))
    }

    @MainActor
    @Test func entitlementServiceTrialExpiresToFree() {
        let defaults = testDefaults()
        let service = EntitlementService(defaults: defaults)

        service.startTrial(days: 0)
        service.refreshTrialState(referenceDate: .now.addingTimeInterval(1))

        #expect(service.tier == .free)
        #expect(!service.isTrialActive)
    }

    @MainActor
    @Test func entitlementServiceProTierUnlocksFeatures() {
        let defaults = testDefaults()
        let service = EntitlementService(defaults: defaults)

        service.activatePro()

        #expect(service.tier == .pro)
        #expect(service.hasAccess(to: .sync))
        #expect(service.hasAccess(to: .smartRouting))
        #expect(service.hasAccess(to: .fullHistory))
    }

    @MainActor
    @Test func onboardingServiceAutoPresentsForEmptyWorkspace() {
        let defaults = testDefaults()
        let service = OnboardingService(defaults: defaults)

        service.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(service.isPresented)
        #expect(service.progress.currentStep == .capture)
    }

    @MainActor
    @Test func onboardingServicePersistsCompletionVersion() {
        let defaults = testDefaults()
        let service = OnboardingService(defaults: defaults)

        service.complete()

        #expect(service.progress.completedVersion == OnboardingService.currentVersion)
        #expect(service.progress.skippedAt == nil)
    }

    @MainActor
    @Test func paywallCoordinatorAppliesCooldownAfterDismissal() {
        let defaults = testDefaults()
        let entitlement = EntitlementService(defaults: defaults)
        let coordinator = PaywallCoordinator(defaults: defaults, entitlement: entitlement)

        let presentation = coordinator.present(feature: .sync, source: .syncSettings)
        #expect(presentation != nil)
        if let presentation {
            coordinator.dismiss(presentation, converted: false)
        }

        #expect(coordinator.isInCooldown(for: .sync))
    }

    @MainActor
    @Test func paywallCoordinatorRunsPendingActionAfterConversion() {
        let defaults = testDefaults()
        let entitlement = EntitlementService(defaults: defaults)
        let coordinator = PaywallCoordinator(defaults: defaults, entitlement: entitlement)
        var didRunPendingAction = false

        let presentation = coordinator.present(
            feature: .smartRouting,
            source: .aiSettings,
            pendingAction: { didRunPendingAction = true }
        )

        #expect(presentation != nil)
        if let presentation {
            coordinator.dismiss(presentation, converted: true)
        }

        #expect(didRunPendingAction)
        #expect(!coordinator.isInCooldown(for: .smartRouting))
    }

    @MainActor
    @Test func conversationStarterServiceCapsFreeLLMResultsAtTwo() async {
        UserDefaults.standard.removeObject(forKey: "grove.conversationStarters")

        let provider = MockLLMProvider()
        provider.responseContent = """
        [
          {"prompt":"P1","label":"REVISIT"},
          {"prompt":"P2","label":"EXPLORE"},
          {"prompt":"P3","label":"RESOLVE"},
          {"prompt":"P4","label":"REFLECT"},
          {"prompt":"P5","label":"SYNTHESIZE"}
        ]
        """

        let service = ConversationStarterService(provider: provider)
        var recent = Item(title: "Recent", type: .note)
        recent.status = .active
        recent.createdAt = .now
        recent.updatedAt = .now
        recent.metadata["summary"] = "A recent thought with enough substance to ground a starter."

        await service.refresh(items: [ItemGraph(item: recent)])

        #expect(service.bubbles.count == ConversationStarterService.maxBubbleCountFree)
    }

    @MainActor
    @Test func conversationStarterServiceShowsNothingWhenLLMUnavailable() async {
        UserDefaults.standard.removeObject(forKey: "grove.conversationStarters")

        let provider = MockLLMProvider()
        provider.responseContent = nil

        let service = ConversationStarterService(provider: provider)
        await service.refresh(items: [])

        #expect(service.bubbles.isEmpty)
    }

    @MainActor
    @Test func conversationStarterServiceDismissRemovesBubble() async {
        UserDefaults.standard.removeObject(forKey: "grove.conversationStarters")

        let provider = MockLLMProvider()
        provider.responseContent = """
        [
          {"prompt":"P1","label":"REVISIT"},
          {"prompt":"P2","label":"EXPLORE"},
          {"prompt":"P3","label":"RESOLVE"}
        ]
        """

        let service = ConversationStarterService(provider: provider)
        var recent = Item(title: "Recent", type: .note)
        recent.status = .active
        recent.createdAt = .now
        recent.updatedAt = .now
        recent.metadata["summary"] = "A recent thought with enough substance to ground a starter."

        await service.refresh(items: [ItemGraph(item: recent)])
        let originalCount = service.bubbles.count
        #expect(originalCount > 1)

        service.dismiss(service.bubbles[0])

        #expect(service.bubbles.count == originalCount - 1)
        #expect(service.bubbles.first?.prompt == "P2")
    }

    @MainActor
    @Test func conversationStarterServiceFiltersBubblesByBoardID() async {
        UserDefaults.standard.removeObject(forKey: "grove.conversationStarters")

        let provider = MockLLMProvider()
        provider.responseContent = """
        [
          {"prompt":"P1","label":"EXPLORE","context_id":"recent_items"}
        ]
        """

        let service = ConversationStarterService(provider: provider)

        let board = Board(title: "Philosophy")
        var item = Item(title: "Recent thought", type: .note)
        item.status = .active
        item.createdAt = .now
        item.updatedAt = .now
        item.metadata["summary"] = "A recent thought with enough substance to ground a starter."
        item.boardID = board.id

        await service.refresh(items: [ItemGraph(item: item, board: board)])

        let scoped = service.bubbles(for: board.id, maxResults: 3)
        #expect(scoped.count == 1)
        #expect(scoped.first?.prompt == "P1")
    }

    @MainActor
    @Test func conversationStarterServiceBoardRefreshRetriesAfterEmptyInitialLoad() async {
        UserDefaults.standard.removeObject(forKey: "grove.conversationStarters")

        let provider = MockLLMProvider()
        provider.responseContent = nil
        let service = ConversationStarterService(provider: provider)

        let board = Board(title: "Board")

        await service.refreshBoard(board.id, items: [])
        #expect(service.bubbles(for: board.id, maxResults: 3).isEmpty)

        var item = Item(title: "Board Item", type: .note)
        item.status = .active
        item.createdAt = .now
        item.updatedAt = .now
        item.boardID = board.id

        await service.refreshBoard(board.id, items: [ItemGraph(item: item, board: board)])
        #expect(!service.bubbles(for: board.id, maxResults: 3).isEmpty)
    }

    @Test func conversationPromptPayloadParsesSeedItemIDsFromNotification() {
        let expectedPrompt = "Organize these notes into a coherent board."
        let expectedSeedIDs = [UUID(), UUID(), UUID()]
        let notification = Notification(
            name: .groveStartConversationWithPrompt,
            object: expectedPrompt,
            userInfo: ["seedItemIDs": expectedSeedIDs]
        )

        let payload = NotificationCenter.conversationPromptPayload(from: notification)
        #expect(payload.prompt == expectedPrompt)
        #expect(payload.seedItemIDs == expectedSeedIDs)
    }

    @Test func conversationPromptPayloadDefaultsToEmptySeedItemIDs() {
        let notification = Notification(
            name: .groveStartConversationWithPrompt,
            object: "Start with a blank slate."
        )
        let payload = NotificationCenter.conversationPromptPayload(from: notification)
        #expect(payload.prompt == "Start with a blank slate.")
        #expect(payload.seedItemIDs.isEmpty)
    }

    @Test func conversationOnlyAppearsInHistoryAfterUserMessage() {
        var conversation = ConversationGraph(conversation: Conversation())

        conversation.messages.append(ChatMessage(
            role: .system, content: "system", position: 0, conversationID: conversation.id, isHidden: true
        ))
        conversation.messages.append(ChatMessage(
            role: .assistant, content: "Initial discussion prompt", position: 1, conversationID: conversation.id
        ))

        #expect(!conversation.hasUserMessages)
        #expect(!conversation.isSavedToHistory)

        conversation.messages.append(ChatMessage(
            role: .user, content: "My response", position: 2, conversationID: conversation.id
        ))

        #expect(conversation.hasUserMessages)
        #expect(conversation.isSavedToHistory)
    }

    @MainActor
    @Test func dialecticalChatHistoryExcludesAssistantOnlyConversations() throws {
        let database = try AppDatabase.openInMemory()
        let viewModel = DialecticalChatViewModel(database: database)

        var assistantOnly = ConversationGraph(conversation: Conversation())
        assistantOnly.messages.append(ChatMessage(
            role: .assistant, content: "Prompt", position: 0, conversationID: assistantOnly.id
        ))

        var replied = ConversationGraph(conversation: Conversation())
        replied.messages.append(ChatMessage(
            role: .user, content: "Reply", position: 0, conversationID: replied.id
        ))

        let visible = viewModel.activeConversations(from: [assistantOnly, replied])

        #expect(visible.map(\.id) == [replied.id])
    }

    @MainActor
    @Test func reflectionToolbarToggleClosesEditorThroughSaveAndExitPath() throws {
        let database = try AppDatabase.openInMemory()
        let item = Item(title: "StringBuilder", type: .article)
        try database.write { db in
            try Item.insert { item }.execute(db)
        }

        let viewModel = ItemReaderViewModel(item: ItemGraph(item: item), database: database)
        let center = NotificationCenter.default
        let focusEventRecorder = FocusEventRecorder()

        let enterObserver = center.addObserver(forName: .groveEnterFocusMode, object: nil, queue: nil) { _ in
            focusEventRecorder.events.append(.groveEnterFocusMode)
        }
        let exitObserver = center.addObserver(forName: .groveExitFocusMode, object: nil, queue: nil) { _ in
            focusEventRecorder.events.append(.groveExitFocusMode)
        }

        defer {
            center.removeObserver(enterObserver)
            center.removeObserver(exitObserver)
        }

        viewModel.toggleReflectionEditor { }
        #expect(viewModel.showReflectionEditor)

        guard viewModel.editingBlock != nil else {
            Issue.record("Expected a reflection block to be opened for editing")
            return
        }

        viewModel.modifyEditingBlock { $0.content = "LLMs use a Rust graph runtime." }
        viewModel.toggleReflectionEditor { }

        #expect(!viewModel.showReflectionEditor)
        #expect(viewModel.editingBlock == nil)
        let saved = try #require(try database.read { try ItemGraph.fetch(item.id, in: $0) })
        #expect(saved.reflections.count == 1)
        #expect(saved.reflections.first?.content == "LLMs use a Rust graph runtime.")
        #expect(viewModel.item.reflections == saved.reflections)
        #expect(focusEventRecorder.events == [.groveEnterFocusMode, .groveExitFocusMode])
    }

    @Test func readLaterTomorrowMorningPresetSchedulesAtNineAM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = makeDate(year: 2026, month: 2, day: 19, hour: 16, minute: 30, calendar: calendar)
        let scheduled = ReadLaterPreset.tomorrowMorning.scheduledDate(from: now, calendar: calendar)

        #expect(calendar.component(.year, from: scheduled) == 2026)
        #expect(calendar.component(.month, from: scheduled) == 2)
        #expect(calendar.component(.day, from: scheduled) == 20)
        #expect(calendar.component(.hour, from: scheduled) == 9)
        #expect(calendar.component(.minute, from: scheduled) == 0)
    }

    @Test func readLaterPresetOffsetsRespectConfiguredDayAndHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = makeDate(year: 2026, month: 2, day: 19, hour: 10, minute: 0, calendar: calendar)
        let tomorrowEvening = ReadLaterPreset.tomorrowEvening.scheduledDate(from: now, calendar: calendar)
        let threeDays = ReadLaterPreset.inThreeDays.scheduledDate(from: now, calendar: calendar)

        #expect(calendar.component(.day, from: tomorrowEvening) == 20)
        #expect(calendar.component(.hour, from: tomorrowEvening) == 18)
        #expect(calendar.component(.day, from: threeDays) == 22)
        #expect(calendar.component(.hour, from: threeDays) == 9)
    }

    @MainActor
    @Test func searchViewModelDebouncesQueryUpdates() async throws {
        let database = try AppDatabase.openInMemory()
        let item = Item(title: "SwiftUI Search Overlay", type: .note)
        try await database.write { db in
            try Item.insert { item }.execute(db)
        }

        let viewModel = SearchViewModel(database: database, debounceNanoseconds: 20_000_000)
        viewModel.updateQuery("swiftui")

        #expect(viewModel.totalResultCount == 0)

        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(viewModel.totalResultCount == 1)
    }

    @MainActor
    @Test func searchViewModelCancelsStaleDebouncedQueries() async throws {
        let database = try AppDatabase.openInMemory()
        let item = Item(title: "Cancel stale result", type: .note)
        try await database.write { db in
            try Item.insert { item }.execute(db)
        }

        let viewModel = SearchViewModel(database: database, debounceNanoseconds: 25_000_000)
        viewModel.updateQuery("cancel")
        viewModel.updateQuery("zzzzzz")

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(viewModel.totalResultCount == 0)
    }

    @Test func resolvedSourceURLAddsMissingSchemeAndTrimsWhitespace() {
        let url = resolvedSourceURL(from: "  aeon.co/essays/what-is-history  ")

        #expect(url?.absoluteString == "https://aeon.co/essays/what-is-history")
        #expect(domainFrom("  aeon.co/essays/what-is-history  ") == "aeon.co")
    }

    @Test func resolvedSourceURLPreservesValidURLs() {
        let url = resolvedSourceURL(from: "https://example.com/articles/swiftui")

        #expect(url?.absoluteString == "https://example.com/articles/swiftui")
    }

    @MainActor
    @Test func mobileBoardDetailEffectiveItemsFiltersSmartBoardAndStatus() {
        var board = Board(title: "Smart")
        board.isSmart = true
        board.smartRuleLogic = .or

        let topic = Tag(name: "swift", category: .technology)

        var activeMatching = Item(title: "Active Match", type: .article)
        activeMatching.status = .active

        var dismissedMatching = Item(title: "Dismissed Match", type: .article)
        dismissedMatching.status = .dismissed

        var unrelatedActive = Item(title: "Unrelated", type: .article)
        unrelatedActive.status = .active

        let effective = MobileBoardDetailView.effectiveItems(
            for: BoardGraph(board: board, smartRuleTags: [topic]),
            allItems: [
                ItemGraph(item: activeMatching, tags: [topic]),
                ItemGraph(item: dismissedMatching, tags: [topic]),
                ItemGraph(item: unrelatedActive),
            ]
        )

        #expect(effective.map(\.id) == [activeMatching.id])
    }

    @MainActor
    @Test func mobileBoardDetailManualSortUsesBoardOrder() {
        var board = Board(title: "Manual")
        var first = Item(title: "First", type: .note)
        var second = Item(title: "Second", type: .note)
        var third = Item(title: "Third", type: .note)
        first.status = .active
        second.status = .active
        third.status = .active

        let items = [first, second, third].map { ItemGraph(item: $0) }
        board.itemOrder = [second.id, third.id, first.id]

        let sorted = MobileBoardDetailView.sortedItems(
            items,
            for: BoardGraph(board: board, items: items),
            sortOption: .manual
        )

        #expect(sorted.map(\.id) == [second.id, third.id, first.id])
    }

    @Test func deepLinkRouterConsumesAllRouteIntents() {
        let router = DeepLinkRouter()
        let itemID = UUID()
        let boardID = UUID()
        let chatID = UUID()

        #expect(router.handle(URL(string: "grove://item/\(itemID.uuidString)")!))
        #expect(router.consumeRouteIntent() == .item(itemID))
        #expect(router.consumeRouteIntent() == nil)

        #expect(router.handle(URL(string: "grove://board/\(boardID.uuidString)")!))
        #expect(router.consumeRouteIntent() == .board(boardID))

        #expect(router.handle(URL(string: "grove://chat/\(chatID.uuidString)")!))
        #expect(router.consumeRouteIntent() == .chat(chatID))
    }

    @Test func deepLinkRouterConsumesCaptureAndSearchIntentPayloads() {
        let router = DeepLinkRouter()
        let encodedURL = "https%3A%2F%2Fexample.com%2Farticle"
        #expect(router.handle(URL(string: "grove://capture?url=\(encodedURL)")!))
        #expect(router.consumeRouteIntent() == .capture(prefillURL: "https://example.com/article"))

        #expect(router.handle(URL(string: "grove://search?q=swiftui")!))
        #expect(router.consumeRouteIntent() == .search(query: "swiftui"))
    }

    @Test func nudgeSettingsOnlyEnableActiveEngineCategories() {
        let previousResurface = NudgeSettings.resurfaceEnabled
        let previousStaleInbox = NudgeSettings.staleInboxEnabled

        NudgeSettings.resurfaceEnabled = true
        NudgeSettings.staleInboxEnabled = true

        #expect(NudgeSettings.isEnabled(for: .resurface))
        #expect(NudgeSettings.isEnabled(for: .staleInbox))
        #expect(!NudgeSettings.isEnabled(for: .connectionPrompt))
        #expect(!NudgeSettings.isEnabled(for: .streak))
        #expect(!NudgeSettings.isEnabled(for: .continueCourse))
        #expect(!NudgeSettings.isEnabled(for: .reflectionPrompt))
        #expect(!NudgeSettings.isEnabled(for: .contradiction))
        #expect(!NudgeSettings.isEnabled(for: .knowledgeGap))
        #expect(!NudgeSettings.isEnabled(for: .synthesisPrompt))
        #expect(!NudgeSettings.isEnabled(for: .dialecticalCheckIn))

        NudgeSettings.resurfaceEnabled = previousResurface
        NudgeSettings.staleInboxEnabled = previousStaleInbox
    }

    @Test func nudgeSettingsRespectActiveCategoryToggles() {
        let previousResurface = NudgeSettings.resurfaceEnabled
        let previousStaleInbox = NudgeSettings.staleInboxEnabled

        NudgeSettings.resurfaceEnabled = false
        NudgeSettings.staleInboxEnabled = false

        #expect(!NudgeSettings.isEnabled(for: .resurface))
        #expect(!NudgeSettings.isEnabled(for: .staleInbox))

        NudgeSettings.resurfaceEnabled = previousResurface
        NudgeSettings.staleInboxEnabled = previousStaleInbox
    }

    @Test func systemNotificationsRequireExplicitOptIn() {
        let key = "nudge.notifications.enabled"
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(!NudgeSettings.notificationsEnabled)
    }

    @MainActor
    @Test func nudgeGenerationSweepsNudgesThatCanNoLongerReachTheUser() throws {
        let key = "nudge.notifications.enabled"
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        NudgeSettings.notificationsEnabled = false

        let database = try AppDatabase.openInMemory()

        // No notification surface, and Home only lists resurface nudges.
        let staleInbox = Nudge(type: .staleInbox, message: "8 items waiting")

        // Home filters targetless resurface nudges out, but the pending guard
        // in the generator still counted them.
        let orphanResurface = Nudge(type: .resurface, message: "Revisit?")

        // Control: reachable, must survive untouched.
        let target = Item(title: "Still here", type: .note)
        let liveResurface = Nudge(type: .resurface, message: "Revisit?", targetItemID: target.id)
        try database.write { db in
            try Item.insert { target }.execute(db)
            try Nudge.insert { [staleInbox, orphanResurface, liveResurface] }.execute(db)
        }

        func status(of nudge: Nudge) throws -> NudgeStatus? {
            try database.read { try Nudge.find(nudge.id).fetchOne($0)?.status }
        }

        let engine = NudgeEngine(database: database)
        engine.generateNudges()

        #expect(try status(of: staleInbox) == .dismissed)
        #expect(try status(of: orphanResurface) == .dismissed)
        #expect(try status(of: liveResurface) == .pending)

        // Idempotent: a second run leaves the swept nudges exactly as they are.
        engine.generateNudges()
        #expect(try status(of: staleInbox) == .dismissed)
        #expect(try status(of: orphanResurface) == .dismissed)
        #expect(try status(of: liveResurface) == .pending)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? .now
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "grove.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

}
