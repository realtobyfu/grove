import SwiftUI
import SwiftData
import StoreKit

#if !SHARE_EXTENSION
@main
#endif
struct GroveApp: App {
    let modelContainer: ModelContainer
    @State private var syncService = SyncService()
    @State private var entitlementService = EntitlementService.shared
    @State private var onboardingService = OnboardingService.shared
    @State private var paywallCoordinator = PaywallCoordinator.shared
    @State private var storeKitService = StoreKitService.shared
    @State private var conversationStarterService = ConversationStarterService.shared
    @State private var coachMarkService = CoachMarkService.shared
    @State private var feedDiscoveryService = FeedDiscoveryService.shared
    @State private var feedFetchService = FeedFetchService.shared
    #if os(iOS)
    @State private var deepLinkRouter = DeepLinkRouter()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        modelContainer = SharedModelContainer.makeForApp()
        #if !SHARE_EXTENSION
        GroveIntentModelStore.configure(with: modelContainer)
        #endif
    }

    /// Newsletter pipeline: fetch new issues from enabled feeds (4h interval
    /// enforced inside the service) and discover feeds on domains the user
    /// saves from (24h cooldown, creates disabled suggestion sources only).
    private func refreshFeedPipeline() async {
        let context = modelContainer.mainContext
        await feedFetchService.refreshIfNeeded(in: context)
        await feedDiscoveryService.discoverFeeds(in: context)
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView(syncService: syncService)
                .task {
                    NudgeNotificationService.shared.configure()
                    let context = modelContainer.mainContext
                    AnnotationMigrationService.migrateIfNeeded(context: context)
                    FeedSuggestionMigrationService.migrateIfNeeded(context: context)
                    storeKitService.start()
                    #if !SHARE_EXTENSION
                    await GroveSpotlightIndexer.refreshAll(using: modelContainer)
                    #endif
                    let items: [Item] = context.fetchAll()
                    await EmbeddingIndexService.shared.indexItems(items.map(EmbeddingIndexService.snapshot))
                    await TensionDetectionService(modelContext: context).runIfDue()
                    await refreshFeedPipeline()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await refreshFeedPipeline() }
                }
                .environment(entitlementService)
                .environment(onboardingService)
                .environment(paywallCoordinator)
                .environment(storeKitService)
                .environment(conversationStarterService)
                .environment(coachMarkService)
                .environment(feedDiscoveryService)
                .environment(feedFetchService)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .commands {
            GroveMenuCommands()
        }

        Settings {
            TabView {
                GeneralSettingsView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                AccountSettingsView()
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle")
                    }

                AISettingsView()
                    .tabItem {
                        Label("AI", systemImage: "sparkles")
                    }

                NudgeSettingsView()
                    .tabItem {
                        Label("Nudges", systemImage: "bell")
                    }

                SubscriptionsSettingsView()
                    .tabItem {
                        Label("Following", systemImage: "newspaper")
                    }

                ShortcutsSettingsView()
                    .tabItem {
                        Label("Shortcuts", systemImage: "keyboard")
                    }
            }
            .frame(width: 640, height: 500)
            .environment(entitlementService)
            .environment(onboardingService)
            .environment(paywallCoordinator)
            .environment(storeKitService)
            .environment(conversationStarterService)
            .environment(coachMarkService)
            .environment(feedDiscoveryService)
            .environment(feedFetchService)
        }
        .modelContainer(modelContainer)
        #else
        // iOS: MobileRootView uses TabRootView with .sidebarAdaptable (sidebar on iPad landscape, tabs elsewhere)
        WindowGroup {
            MobileRootView()
                .task {
                    let context = modelContainer.mainContext
                    AnnotationMigrationService.migrateIfNeeded(context: context)
                    FeedSuggestionMigrationService.migrateIfNeeded(context: context)
                    ExtensionItemProcessor.processIfNeeded(context: context)
                    storeKitService.start()
                    #if !SHARE_EXTENSION
                    await GroveSpotlightIndexer.refreshAll(using: modelContainer)
                    #endif
                    let items: [Item] = context.fetchAll()
                    await EmbeddingIndexService.shared.indexItems(items.map(EmbeddingIndexService.snapshot))
                    await TensionDetectionService(modelContext: context).runIfDue()
                    await refreshFeedPipeline()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await refreshFeedPipeline() }
                }
                .onOpenURL { url in
                    deepLinkRouter.handle(url)
                }
                .environment(deepLinkRouter)
                .environment(entitlementService)
                .environment(onboardingService)
                .environment(paywallCoordinator)
                .environment(storeKitService)
                .environment(conversationStarterService)
                .environment(coachMarkService)
                .environment(feedDiscoveryService)
                .environment(feedFetchService)
        }
        .modelContainer(modelContainer)
        #endif
    }
}

// MARK: - Menu Bar Commands

#if os(macOS)
struct GroveMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Capture") {
                NotificationCenter.default.post(name: .groveCaptureBar, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Note") {
                NotificationCenter.default.post(name: .groveNewNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Board") {
                NotificationCenter.default.post(name: .groveNewBoard, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .importExport) {
            Button("Export Selected Item...") {
                NotificationCenter.default.post(name: .groveExportItem, object: nil)
            }
        }

        CommandMenu("Navigate") {
            Button("Search") {
                NotificationCenter.default.post(name: .groveToggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Button("Go to Home") {
                NotificationCenter.default.post(name: .groveGoToHome, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            // Board switching Cmd+1 through Cmd+9
            ForEach(1...9, id: \.self) { index in
                Button("Go to Board \(index)") {
                    NotificationCenter.default.post(name: .groveGoToBoard, object: index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }

        }

        CommandMenu("View") {
            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: .groveToggleInspector, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Toggle Dialectics") {
                NotificationCenter.default.post(name: .groveToggleChat, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            // Reader text size, on the shortcuts every browser uses. The reader
            // decides what they mean for the page on screen — type scale in
            // Reader mode, page zoom on the live page.
            Button("Bigger Text") {
                NotificationCenter.default.post(name: .groveReaderTextLarger, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Smaller Text") {
                NotificationCenter.default.post(name: .groveReaderTextSmaller, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                NotificationCenter.default.post(name: .groveReaderTextReset, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
        }
    }
}

#endif
