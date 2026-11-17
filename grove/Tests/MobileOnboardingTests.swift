import Foundation
import Testing
@testable import grove

@MainActor
struct MobileOnboardingTests {
    @Test func firesForEmptyWorkspaceOnFirstLaunch() {
        let service = OnboardingService(defaults: testDefaults())

        service.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(service.isPresented)
        #expect(service.progress.currentStep == .capture)
    }

    @Test(arguments: [(1, 0), (0, 1), (3, 2)])
    func doesNotFireWithExistingContent(itemCount: Int, boardCount: Int) {
        let service = OnboardingService(defaults: testDefaults())

        service.evaluateAutoPresentation(itemCount: itemCount, boardCount: boardCount)

        #expect(!service.isPresented)
    }

    @Test func doesNotFireAfterCompletionOnALaterLaunch() {
        let defaults = testDefaults()
        OnboardingService(defaults: defaults).complete()

        let relaunched = OnboardingService(defaults: defaults)
        relaunched.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(!relaunched.isPresented)
    }

    @Test func doesNotFireAfterSkipOnALaterLaunch() {
        let defaults = testDefaults()
        OnboardingService(defaults: defaults).skip()

        let relaunched = OnboardingService(defaults: defaults)
        relaunched.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(!relaunched.isPresented)
    }

    @Test func firesWhenOnlyAnEarlierVersionWasCompleted() {
        let defaults = testDefaults()
        defaults.set(OnboardingService.currentVersion - 1, forKey: "grove.onboarding.completedVersion")
        let service = OnboardingService(defaults: defaults)

        service.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(service.isPresented)
    }

    /// The root view can reappear; emptying a workspace mid-session must not
    /// bring the welcome up over it.
    @Test func evaluatesOnlyOncePerLaunch() {
        let service = OnboardingService(defaults: testDefaults())

        service.evaluateAutoPresentation(itemCount: 2, boardCount: 0)
        service.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(!service.isPresented)
    }

    @Test func doesNotRepresentAfterCompletingInTheSameLaunch() {
        let service = OnboardingService(defaults: testDefaults())
        service.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        service.complete()
        service.evaluateAutoPresentation(itemCount: 0, boardCount: 0)

        #expect(!service.isPresented)
    }

    @Test func replayStillPresentsAfterCompletion() {
        let service = OnboardingService(defaults: testDefaults())
        service.complete()

        service.presentReplay()

        #expect(service.isPresented)
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "grove.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
