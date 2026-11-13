import Foundation
import SwiftData
import Testing
@testable import grove

/// Free-tier limits apply only to cloud AI calls.
@MainActor
struct EntitlementMeteringTests {
    private func defaults() -> UserDefaults {
        let name = "EntitlementMeteringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func freeUserOnCloudStopsAtTheLimit() {
        let service = EntitlementService(defaults: defaults(), usesCloudAI: { true })

        for _ in 0..<MeteredFeature.dialectics.freeLimit {
            #expect(service.canUse(.dialectics))
            service.recordUse(.dialectics)
        }

        #expect(!service.canUse(.dialectics))
        #expect(service.remaining(.dialectics) == 0)
        #expect(service.hasUsageLimits)
    }

    @Test func freeUserOnDeviceIsNeverLimited() {
        let store = defaults()
        let service = EntitlementService(defaults: store, usesCloudAI: { false })

        for _ in 0..<(MeteredFeature.dialectics.freeLimit * 2) {
            service.recordUse(.dialectics)
        }

        #expect(service.canUse(.dialectics))
        #expect(service.remaining(.dialectics) == Int.max)
        #expect(!service.hasUsageLimits)

        // On-device uses were never counted, so switching to cloud starts fresh.
        let cloud = EntitlementService(defaults: store, usesCloudAI: { true })
        #expect(cloud.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit)
    }

    @Test func proOnCloudIsNotLimited() {
        let service = EntitlementService(defaults: defaults(), usesCloudAI: { true })
        service.activatePro()

        #expect(!service.hasUsageLimits)
        #expect(service.canUse(.autoTagging))
        #expect(service.remaining(.autoTagging) == Int.max)
    }

    // MARK: - Cloud chat, metered per conversation at the first cloud send

    @Test func aConversationCountsOnceHoweverManyMessages() {
        let service = EntitlementService(defaults: defaults(), usesCloudAI: { true })
        let conversation = UUID()

        for _ in 0..<5 {
            #expect(service.canSendCloudMessage(in: conversation))
            service.recordCloudMessage(in: conversation)
        }
        #expect(service.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit - 1)
    }

    @Test func freeUserStopsAtTheLimitButKeepsTheirCountedConversations() {
        let service = EntitlementService(defaults: defaults(), usesCloudAI: { true })
        let counted = (0..<MeteredFeature.dialectics.freeLimit).map { _ in UUID() }
        for id in counted {
            #expect(service.canSendCloudMessage(in: id))
            service.recordCloudMessage(in: id)
        }

        #expect(!service.canSendCloudMessage(in: UUID()))
        #expect(!service.canUse(.dialectics))
        #expect(service.remaining(.dialectics) == 0)
        // Conversations already counted this month carry on.
        #expect(service.canSendCloudMessage(in: counted[0]))
    }

    @Test func conversationsCreatedOnDeviceAreMeteredOnceTheyReachTheCloud() {
        let store = defaults()
        let onDevice = EntitlementService(defaults: store, usesCloudAI: { false })
        let created = (0..<50).map { _ in UUID() }
        for id in created {
            #expect(onDevice.canSendCloudMessage(in: id))
            onDevice.recordCloudMessage(in: id)
        }

        let cloud = EntitlementService(defaults: store, usesCloudAI: { true })
        var allowed = 0
        for id in created where cloud.canSendCloudMessage(in: id) {
            cloud.recordCloudMessage(in: id)
            allowed += 1
        }
        #expect(allowed == MeteredFeature.dialectics.freeLimit)
    }

    @Test func usesCountedByTheOldCounterThisMonthStillCount() throws {
        let store = defaults()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let legacy = MeteredUsage(count: 4, monthKey: formatter.string(from: Date()))
        store.set(try JSONEncoder().encode(legacy), forKey: "grove.usage.dialectics")

        let service = EntitlementService(defaults: store, usesCloudAI: { true })
        #expect(service.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit - 4)
        service.recordCloudMessage(in: UUID())
        #expect(service.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit - 5)
    }

    @Test func aLastMonthsOldCounterDoesNotCount() throws {
        let store = defaults()
        let legacy = MeteredUsage(count: 6, monthKey: "2001-01")
        store.set(try JSONEncoder().encode(legacy), forKey: "grove.usage.dialectics")

        let service = EntitlementService(defaults: store, usesCloudAI: { true })
        #expect(service.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit)
    }

    @Test func proSendsWithoutBeingCounted() {
        let store = defaults()
        let service = EntitlementService(defaults: store, usesCloudAI: { true })
        service.activatePro()
        for _ in 0..<(MeteredFeature.dialectics.freeLimit + 1) {
            let id = UUID()
            #expect(service.canSendCloudMessage(in: id))
            service.recordCloudMessage(in: id)
        }
        service.downgradeToFree()
        #expect(service.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit)
    }

    @Test func theChatServiceRefusesACloudSendPastTheLimitAndRecordsOtherwise() async throws {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "EntitlementMeteringTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let entitlements = EntitlementService(defaults: defaults(), usesCloudAI: { true })
        let provider = MockLLMProvider()
        provider.responseContent = "A reply grounded in your library."
        let chat = DialecticsService(provider: provider, entitlements: entitlements, isCloudBacked: true)

        func newConversation() -> Conversation {
            chat.startConversation(trigger: .userInitiated, seedItems: [], board: nil, context: context)
        }

        // Creating conversations costs nothing; the first send does.
        let first = newConversation()
        #expect(entitlements.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit)
        #expect(await chat.sendMessage(userText: "Hello", conversation: first, context: context) != nil)
        #expect(await chat.sendMessage(userText: "Again", conversation: first, context: context) != nil)
        #expect(entitlements.remaining(.dialectics) == MeteredFeature.dialectics.freeLimit - 1)

        for _ in 1..<MeteredFeature.dialectics.freeLimit {
            _ = await chat.sendMessage(userText: "Hi", conversation: newConversation(), context: context)
        }
        #expect(entitlements.remaining(.dialectics) == 0)

        let blocked = newConversation()
        let messagesBefore = blocked.messages.count
        #expect(!chat.canSendMessage(in: blocked))
        #expect(await chat.sendMessage(userText: "Hi", conversation: blocked, context: context) == nil)
        #expect(chat.hitCloudChatLimit)
        #expect(chat.lastError == DialecticsService.cloudChatLimitMessage)
        #expect(blocked.messages.count == messagesBefore)

        // A conversation that already used the cloud this month carries on.
        #expect(await chat.sendMessage(userText: "More", conversation: first, context: context) != nil)
        #expect(!chat.hitCloudChatLimit)

        // On-device chat is never metered.
        let onDevice = DialecticsService(provider: provider, entitlements: entitlements, isCloudBacked: false)
        #expect(await onDevice.sendMessage(userText: "Hi", conversation: blocked, context: context) != nil)
    }
}
