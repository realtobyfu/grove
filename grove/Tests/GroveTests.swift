import Foundation
import SwiftData
import Testing
@testable import grove

struct GroveTests {
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
    @Test func conversationStarterServiceCapsLLMResultsAtThree() async {
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
        let recent = Item(title: "Recent", type: .note)
        recent.status = .active
        recent.createdAt = .now
        recent.updatedAt = .now

        await service.refresh(items: [recent])

        #expect(service.bubbles.count == 3)
    }

    @MainActor
    @Test func conversationStarterServiceProvidesFallbackWhenNoContext() async {
        UserDefaults.standard.removeObject(forKey: "grove.conversationStarters")

        let provider = MockLLMProvider()
        provider.responseContent = nil

        let service = ConversationStarterService(provider: provider)
        await service.refresh(items: [])

        #expect(service.bubbles.count == 1)
        #expect(service.bubbles.first?.label == "REFLECT")
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
        let item = Item(title: "Recent thought", type: .note)
        item.status = .active
        item.createdAt = .now
        item.updatedAt = .now
        item.boards.append(board)

        await service.refresh(items: [item])

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

        let item = Item(title: "Board Item", type: .note)
        item.status = .active
        item.createdAt = .now
        item.updatedAt = .now
        item.boards.append(board)

        await service.refreshBoard(board.id, items: [item])
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
        let context = try makeInMemoryModelContext()
        let item = Item(title: "SwiftUI Search Overlay", type: .note)
        context.insert(item)
        try context.save()

        let viewModel = SearchViewModel(modelContext: context, debounceNanoseconds: 20_000_000)
        viewModel.updateQuery("swiftui")

        #expect(viewModel.totalResultCount == 0)

        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(viewModel.totalResultCount == 1)
    }

    @MainActor
    @Test func searchViewModelCancelsStaleDebouncedQueries() async throws {
        let context = try makeInMemoryModelContext()
        let item = Item(title: "Cancel stale result", type: .note)
        context.insert(item)
        try context.save()

        let viewModel = SearchViewModel(modelContext: context, debounceNanoseconds: 25_000_000)
        viewModel.updateQuery("cancel")
        viewModel.updateQuery("zzzzzz")

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(viewModel.totalResultCount == 0)
    }

    @MainActor
    @Test func mobileBoardDetailEffectiveItemsFiltersSmartBoardAndStatus() {
        let board = Board(title: "Smart")
        board.isSmart = true
        board.smartRuleLogic = .or

        let topic = Tag(name: "swift", category: .technology)
        board.smartRuleTags.append(topic)

        let activeMatching = Item(title: "Active Match", type: .article)
        activeMatching.status = .active
        activeMatching.tags.append(topic)

        let dismissedMatching = Item(title: "Dismissed Match", type: .article)
        dismissedMatching.status = .dismissed
        dismissedMatching.tags.append(topic)

        let unrelatedActive = Item(title: "Unrelated", type: .article)
        unrelatedActive.status = .active

        let effective = MobileBoardDetailView.effectiveItems(
            for: board,
            allItems: [activeMatching, dismissedMatching, unrelatedActive]
        )

        #expect(effective.map(\.id) == [activeMatching.id])
    }

    @MainActor
    @Test func mobileBoardDetailManualSortUsesBoardOrder() {
        let board = Board(title: "Manual")
        let first = Item(title: "First", type: .note)
        let second = Item(title: "Second", type: .note)
        let third = Item(title: "Third", type: .note)
        first.status = .active
        second.status = .active
        third.status = .active

        board.items.append(first)
        board.items.append(second)
        board.items.append(third)
        board.setManualOrder([second.id, third.id, first.id])

        let sorted = MobileBoardDetailView.sortedItems(
            [first, second, third],
            for: board,
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

    @MainActor
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = Schema([
            Item.self,
            Board.self,
            Tag.self,
            Connection.self,
            Annotation.self,
            ReflectionBlock.self,
            Nudge.self,
            Course.self,
            Conversation.self,
            ChatMessage.self,
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "grove.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

}
