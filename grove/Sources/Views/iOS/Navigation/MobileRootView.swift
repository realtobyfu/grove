import SwiftUI
import SwiftData

/// Top-level iOS entry point.
/// iPad (regular width): 3-column NavigationSplitView via iPadRootView.
/// iPhone (compact width): Tab-based navigation via TabRootView.
struct MobileRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(OnboardingService.self) private var onboarding
    @State private var showOnboarding = false
    @State private var nudgeEngine: NudgeEngine?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadRootView()
            } else {
                TabRootView()
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            MobileOnboardingView()
        }
        #endif
        .onChange(of: onboarding.isPresented) { _, isPresented in
            showOnboarding = isPresented
        }
        .mobileNudgeHandler()
        .onAppear {
            evaluateOnboarding()
            showOnboarding = onboarding.isPresented
            // Configure push notifications and start nudge engine
            NudgeNotificationService.shared.configure()
            if nudgeEngine == nil {
                let engine = NudgeEngine(modelContext: modelContext)
                engine.startSchedule()
                nudgeEngine = engine
            }
        }
    }

    /// One-shot count rather than `@Query`: the service only evaluates once per
    /// launch, so the root view needn't re-render on every library change. A
    /// failed fetch leaves the welcome hidden instead of showing it over content.
    private func evaluateOnboarding() {
        guard let itemCount = try? modelContext.fetchCount(FetchDescriptor<Item>()),
              let boardCount = try? modelContext.fetchCount(FetchDescriptor<Board>()) else { return }
        onboarding.evaluateAutoPresentation(itemCount: itemCount, boardCount: boardCount)
    }
}
