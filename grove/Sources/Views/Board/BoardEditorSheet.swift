import SwiftUI

struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedIcon: String

    private let isEditing: Bool
    /// The board's stored color, passed straight back through on save.
    /// Boards are monochrome now, but existing colors are data — editing a
    /// board must not quietly repaint it, and new boards get `nil`, which is
    /// the neutral every board surface already falls back to.
    private let preservedColorHex: String?
    private let onSave: (String, String?, String?) -> Void

    private static let defaultIcon = "folder"

    init(
        board: Board? = nil,
        onSave: @escaping (String, String?, String?) -> Void
    ) {
        if let board {
            self.isEditing = true
            _title = State(initialValue: board.title)
            _selectedIcon = State(initialValue: board.icon ?? Self.defaultIcon)
            self.preservedColorHex = board.color
        } else {
            self.isEditing = false
            _title = State(initialValue: "")
            _selectedIcon = State(initialValue: Self.defaultIcon)
            self.preservedColorHex = nil
        }
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Board Name") {
                    TextField("Enter board name", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.groveBody)
                }

                Section("Icon") {
                    iconPicker
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
        .frame(width: 420, height: 400)
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Board" : "New Board")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(isEditing ? "Save" : "Create") {
                let icon = selectedIcon.isEmpty ? nil : selectedIcon
                onSave(title, icon, preservedColorHex)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    // MARK: - Icon Picker

    private static let iconOptions: [String] = [
        "folder", "book", "laptopcomputer", "brain",
        "lightbulb", "star", "heart", "hammer",
        "paintbrush", "music.note", "globe", "atom",
        "function", "terminal", "cpu", "network",
        "chart.bar", "doc.text", "photo", "film",
        "gamecontroller", "graduationcap", "flask", "wrench",
        "leaf", "bolt", "eye", "swift",
        "person.2", "map", "flag", "bookmark"
    ]

    /// Icons read in ink, never in color. The selected one steps up to full
    /// ink inside a 3pt-radius outline — the same weight-and-rule hierarchy
    /// the rest of the app uses instead of a tint.
    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
            ForEach(Self.iconOptions, id: \.self) { icon in
                let isSelected = selectedIcon == icon
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.textPrimary, lineWidth: isSelected ? 1 : 0)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
