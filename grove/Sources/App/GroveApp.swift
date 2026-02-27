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
    #if os(iOS)
    @State private var deepLinkRouter = DeepLinkRouter()
    #endif

    init() {
        modelContainer = SharedModelContainer.makeForApp()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView(syncService: syncService)
                .task {
                    NudgeNotificationService.shared.configure()
                    let context = modelContainer.mainContext
                    AnnotationMigrationService.migrateIfNeeded(context: context)
                    storeKitService.start()
                }
                .environment(entitlementService)
                .environment(onboardingService)
                .environment(paywallCoordinator)
                .environment(storeKitService)
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
        }
        #else
        // iOS: MobileRootView switches between TabRootView (iPhone) and iPadRootView (iPad)
        WindowGroup {
            MobileRootView()
                .task {
                    let context = modelContainer.mainContext
                    AnnotationMigrationService.migrateIfNeeded(context: context)
                    ExtensionItemProcessor.processIfNeeded(context: context)
                    storeKitService.start()
                }
                .onOpenURL { url in
                    deepLinkRouter.handle(url)
                }
                .environment(deepLinkRouter)
                .environment(entitlementService)
                .environment(onboardingService)
                .environment(paywallCoordinator)
                .environment(storeKitService)
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
    @State private var showInvalidLink = false
    @FocusState private var isFocused: Bool

    private var validLink: String? {
        normalizedLink(from: linkText)
    }

    private var helperText: String {
        if showSaved {
            return "Link saved."
        }
        if showInvalidLink {
            return "Enter a valid http(s) link."
        }
        return "Paste a link and press Return."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Quick Capture")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: Spacing.sm) {
                Image(systemName: "link")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                TextField("https://example.com", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .font(.groveBody)
                    .focused($isFocused)
                    .onSubmit {
                        captureLink()
                    }
                    .onChange(of: linkText) { _, _ in
                        showSaved = false
                        showInvalidLink = false
                    }

                Button {
                    captureLink()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.groveBody)
                        .foregroundStyle(validLink == nil ? Color.textTertiary : Color.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(validLink == nil)
                .accessibilityLabel("Capture link")
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

    private func captureLink() {
        guard let validLink else {
            showSaved = false
            showInvalidLink = true
            return
        }

        let captureService = CaptureService(modelContext: modelContext)
        _ = captureService.captureItem(input: validLink)

        linkText = ""
        showInvalidLink = false
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
