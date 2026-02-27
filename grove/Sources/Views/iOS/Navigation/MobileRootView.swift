import SwiftUI

/// Top-level iOS entry point that switches between iPhone and iPad layouts
/// based on horizontal size class. Compact → TabRootView, Regular → iPadRootView.
struct MobileRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootView()
        } else {
            TabRootView()
        }
    }
}
