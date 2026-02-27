import SwiftUI
import SwiftData

/// iPhone tab-based navigation with 5 tabs.
/// Each tab wraps a NavigationStack so that pushed views get their own nav bar.
/// Actual tab content views (MobileHomeView, MobileInboxView, etc.) will replace
/// the placeholder Text views as they are implemented in P3–P9.
struct TabRootView: View {
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query private var allItems: [Item]
    @State private var selectedTab: Tab = .home

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    enum Tab: String, Hashable {
        case home, inbox, library, chat, more
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MobileHomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(Tab.home)

            NavigationStack {
                MobileInboxView()
            }
            .tabItem {
                Label("Inbox", systemImage: "tray")
            }
            .tag(Tab.inbox)
            .badge(inboxCount)

            NavigationStack {
                MobileLibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                MobileConversationListView()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(Tab.chat)

            NavigationStack {
                Text("More")
                    .font(.groveTitle)
                    .foregroundStyle(Color.textSecondary)
                    .navigationTitle("More")
            }
            .tabItem {
                Label("More", systemImage: "ellipsis")
            }
            .tag(Tab.more)
        }
        .overlay(alignment: .bottomTrailing) {
            // Show floating capture button on content tabs (not Chat or More)
            if [Tab.home, .inbox, .library].contains(selectedTab) {
                FloatingCaptureButton()
                    .padding(.trailing, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .onChange(of: deepLinkRouter.selectedTab) { _, newTab in
            if let newTab {
                selectedTab = newTab
            }
        }
    }
}
