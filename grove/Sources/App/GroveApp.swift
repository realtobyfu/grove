import SwiftUI
import SwiftData

@main
struct GroveApp: App {
    let modelContainer: ModelContainer
    @State private var syncService = SyncService()

    init() {
        let schema = Schema([
            Item.self,
            Board.self,
            Tag.self,
            Connection.self,
            Annotation.self,
            ReflectionBlock.self,
            Nudge.self,
            Course.self,
            Conversation.self,
            ChatMessage.self,
        ])

        do {
            if SyncSettings.syncEnabled {
                // CloudKit-backed configuration for sync
                let config = ModelConfiguration(
                    "Grove",
                    schema: schema,
                    cloudKitDatabase: .automatic
                )
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } else {
                // Local-only configuration (default)
                let config = ModelConfiguration(
                    "Grove",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            }
        } catch {
            // CloudKit may fail if not configured — fall back to local-only
            do {
                let fallbackConfig = ModelConfiguration(
                    "Grove",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                modelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
                SyncSettings.syncEnabled = false
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(syncService: syncService)
                .task {
                    let context = modelContainer.mainContext
                    AnnotationMigrationService.migrateIfNeeded(context: context)
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .commands {
            GroveMenuCommands()
        }

        MenuBarExtra("Grove", systemImage: "leaf") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Window("Quick Capture", id: "quick-capture") {
            QuickCapturePanel()
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Settings {
            TabView {
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
            }
            .frame(width: 500, height: 500)
        }
    }
}

// MARK: - Menu Bar Commands

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

            Button("Toggle Dialectical Chat") {
                NotificationCenter.default.post(name: .groveToggleChat, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            Button {
                openWindow(id: "quick-capture")
            } label: {
                Label("Quick Capture", systemImage: "plus.circle")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            InboxCountView()

            Divider()

            Button("Quit Grove") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }
}

struct InboxCountView: View {
    @Query private var allItems: [Item]

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    var body: some View {
        Label("\(inboxCount) items in Inbox", systemImage: "tray")
            .font(.groveMeta)
            .foregroundStyle(Color.textSecondary)
    }
}
