import Foundation
import SwiftData
import Testing
@testable import grove

struct GroveTests {
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

}
