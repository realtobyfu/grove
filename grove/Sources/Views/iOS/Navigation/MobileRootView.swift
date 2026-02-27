import SwiftUI

/// Top-level iOS entry point that switches between iPhone and iPad layouts
/// based on horizontal size class. Compact → TabRootView, Regular → iPadRootView.
/// Presents onboarding as a full-screen cover when OnboardingService.isPresented is true.
struct MobileRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(OnboardingService.self) private var onboarding
    @State private var showOnboarding = false

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
        .onAppear {
            showOnboarding = onboarding.isPresented
        }
    }
}
