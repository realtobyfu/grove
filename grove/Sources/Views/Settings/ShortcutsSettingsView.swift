import SwiftUI

/// Settings view listing all keyboard shortcuts for quick reference.
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Capture") {
                shortcutRow("Capture", shortcut: "⌘N")
                shortcutRow("New Note", shortcut: "⌘⇧N")
            }

            Section("Navigation") {
                shortcutRow("Search", shortcut: "⌘F")
                shortcutRow("Go to Today", shortcut: "⌘0")
                shortcutRow("Go to Board 1–9", shortcut: "⌘1 – ⌘9")
                shortcutRow("New Board", shortcut: "⌘⇧B")
                shortcutRow("Review flashcards", shortcut: "⌘⇧R")
            }

            Section("View") {
                shortcutRow("Toggle Inspector", shortcut: "⌘]")
                shortcutRow("Toggle Chat", shortcut: "⌘⇧D")
            }

            Section("Library") {
                shortcutRow("Move to Board…", shortcut: "⌘⇧M")
            }

            Section("Reader") {
                shortcutRow("Bigger Text", shortcut: "⌘+")
                shortcutRow("Smaller Text", shortcut: "⌘−")
                shortcutRow("Actual Size", shortcut: "⌘⇧0")
            }

            Section("Export") {
                shortcutRow("Export Selected Item...", shortcut: "Menu only")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.groveBody)
            Spacer()
            Text(shortcut)
                .font(.groveShortcut)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .stroke(Color.borderInput)
                )
        }
    }
}
