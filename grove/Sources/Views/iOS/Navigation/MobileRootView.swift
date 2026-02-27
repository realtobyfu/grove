import SwiftUI

/// Top-level iOS entry point. Uses unified TabRootView with `.sidebarAdaptable`
/// which automatically shows sidebar on iPad landscape and tabs on iPhone/iPad portrait.
struct MobileRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingService.self) private var onboarding
    @State private var showOnboarding = false
    @State private var nudgeEngine: NudgeEngine?

    var body: some View {
        TabRootView()
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
                let engine = NudgeEngine(modelContext: modelContext)
                engine.startSchedule()
                nudgeEngine = engine
            }
        }
    }
}
