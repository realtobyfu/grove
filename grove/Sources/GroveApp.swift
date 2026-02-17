import SwiftUI
import SwiftData

@main
struct GroveApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for:
                Item.self,
                Board.self,
                Tag.self,
                Connection.self,
                Annotation.self,
                Nudge.self,
                Course.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
            }
            .frame(width: 500, height: 450)
        }
    }
}

// MARK: - Menu Bar Commands

struct GroveMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                NotificationCenter.default.post(name: .groveNewNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Quick Capture") {
                NotificationCenter.default.post(name: .groveQuickCapture, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandMenu("Navigate") {
            Button("Search") {
                NotificationCenter.default.post(name: .groveToggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Button("Go to Inbox") {
                NotificationCenter.default.post(name: .groveGoToInbox, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            // Board switching Cmd+1 through Cmd+9
            ForEach(1...9, id: \.self) { index in
                Button("Go to Board \(index)") {
                    NotificationCenter.default.post(name: .groveGoToBoard, object: index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }

            Divider()

            Button("Go to Tags") {
                NotificationCenter.default.post(name: .groveGoToTags, object: nil)
            }
        }

        CommandMenu("View") {
            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: .groveToggleInspector, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)
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
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
