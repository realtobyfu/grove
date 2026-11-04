import SwiftUI

/// Top-level iOS entry point.
/// iPad (regular width): 3-column NavigationSplitView via iPadRootView.
/// iPhone (compact width): Tab-based navigation via TabRootView.
struct MobileRootView: View {
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
            showOnboarding = onboarding.isPresented
            // Configure push notifications and start nudge engine
            NudgeNotificationService.shared.configure()
            if nudgeEngine == nil {
                let engine = NudgeEngine()
                engine.startSchedule()
                nudgeEngine = engine
            }
        }
    }
}
