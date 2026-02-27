import SwiftUI

/// Top-level iOS entry point that switches between iPhone and iPad layouts
/// based on horizontal size class. Compact → TabRootView, Regular → iPadRootView.
/// Presents onboarding as a full-screen cover when OnboardingService.isPresented is true.
struct MobileRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
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
                let engine = NudgeEngine(modelContext: modelContext)
                engine.startSchedule()
                nudgeEngine = engine
            }
        }
    }
}
