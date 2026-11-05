import Foundation
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
}
