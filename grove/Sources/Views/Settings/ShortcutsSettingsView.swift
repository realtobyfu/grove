import SwiftUI

/// Settings view listing all keyboard shortcuts for quick reference.
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Capture") {
                shortcutRow("Capture", shortcut: "⌘N")
                shortcutRow("New Note", shortcut: "⌘⇧N")
                shortcutRow("Quick Capture", shortcut: "⌘⇧K")
            }

            Section("Navigation") {
                shortcutRow("Search", shortcut: "⌘F")
                shortcutRow("Go to Home", shortcut: "⌘0")
                shortcutRow("Go to Board 1–9", shortcut: "⌘1 – ⌘9")
                shortcutRow("New Board", shortcut: "⌘⇧B")
            }

            Section("View") {
                shortcutRow("Toggle Inspector", shortcut: "⌘]")
                shortcutRow("Toggle Dialectics", shortcut: "⌘⇧D")
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
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.borderInput)
                )
        }
    }
}
