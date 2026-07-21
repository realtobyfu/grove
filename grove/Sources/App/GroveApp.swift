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

        MenuBarExtra {
            MenuBarView()
                .environment(entitlementService)
                .environment(onboardingService)
                .environment(paywallCoordinator)
                .environment(storeKitService)
                .environment(conversationStarterService)
                .environment(coachMarkService)
                .environment(feedDiscoveryService)
                .environment(feedFetchService)
        } label: {
            Label("Grove", systemImage: "leaf")
                .labelStyle(.iconOnly)
                .scaleEffect(x: -1, y: 1)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Window("Quick Capture", id: "quick-capture") {
            QuickCapturePanel()
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Settings {
            TabView {
                ProSettingsView()
                    .tabItem {
                        Label("Pro", systemImage: "crown")
                    }

                NudgeSettingsView()
                    .tabItem {
                        Label("Nudges", systemImage: "bell")
                    }
                SubscriptionsSettingsView()
                    .tabItem {
                        Label("Newsletters", systemImage: "newspaper")
                    }
                AISettingsView()
                    .tabItem {
                        Label("AI", systemImage: "sparkles")
                    }

                AppearanceSettingsView()
                    .tabItem {
                        Label("Appearance", systemImage: "paintbrush")
                    }

                SyncSettingsView()
                    .tabItem {
                        Label("Sync", systemImage: "icloud")
                    }
                ShortcutsSettingsView()
                    .tabItem {
                        Label("Shortcuts", systemImage: "keyboard")
                    }
                FeedbackSettingsView()
                    .tabItem {
                        Label("Feedback", systemImage: "envelope")
                    }
            }
            .frame(width: 500, height: 500)
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
    @Environment(\.openWindow) private var openWindow

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

            Divider()

            Button("Quick Capture") {
                openWindow(id: "quick-capture")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
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
        }
    }
}

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var linkText = ""
    @State private var showSaved = false
    @State private var savedMessage = ""
    @FocusState private var isFocused: Bool

    private var trimmedInput: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validLink: String? {
        normalizedLink(from: linkText)
    }

    private var helperText: String {
        if showSaved {
            return savedMessage
        }
        return "Paste a link or jot a note, then press Return."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Quick Capture")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.and.pencil")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                TextField("Paste a link or jot a note", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .font(.groveBody)
                    .focused($isFocused)
                    .onSubmit {
                        capture()
                    }
                    .onChange(of: linkText) { _, _ in
                        showSaved = false
                    }

                Button {
                    capture()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.groveBody)
                        .foregroundStyle(trimmedInput.isEmpty ? Color.textTertiary : Color.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(trimmedInput.isEmpty)
                .accessibilityLabel("Capture")
            }

            Text(helperText)
                .font(.groveMeta)
                .foregroundStyle(showSaved ? Color.textSecondary : Color.textTertiary)

            Button("Quit Grove") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(Spacing.sm)
        .frame(width: 320)
        .onAppear {
            isFocused = true
        }
    }

    private func capture() {
        guard !trimmedInput.isEmpty else { return }

        // URL fast path: normalized http(s) links capture exactly as before;
        // anything else is saved as a note.
        let input = validLink ?? trimmedInput
        let captureService = CaptureService(modelContext: modelContext)
        let result = captureService.captureItemDetailed(input: input)

        if result.isDuplicate {
            savedMessage = "Already in your library."
        } else {
            savedMessage = result.item.type == .note ? "Note saved." : "Link saved."
        }

        linkText = ""
        withAnimation(.easeInOut(duration: 0.15)) {
            showSaved = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.2)) {
                showSaved = false
            }
        }
    }

    private func normalizedLink(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = validHTTPURL(trimmed) {
            return direct.absoluteString
        }
        if !trimmed.contains("://"), let prefixed = validHTTPURL("https://\(trimmed)") {
            return prefixed.absoluteString
        }
        return nil
    }

    private func validHTTPURL(_ raw: String) -> URL? {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        return url
    }
}
#endif
