import SwiftUI

struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedIcon: String
    @State private var nudgeFrequencyHours: Int

    private let isEditing: Bool
    private let wasSmartBoard: Bool
    /// The board's stored color, passed straight back through on save.
    /// Boards are monochrome now, but existing colors are data — editing a
    /// board must not quietly repaint it, and new boards get `nil`, which is
    /// the neutral every board surface already falls back to.
    private let preservedColorHex: String?
    private let onSave: (String, String?, String?, Int) -> Void

    private static let defaultIcon = "folder"

    /// Nudge frequency options: 0 = global default, -1 = disabled, or custom hours
    private static let nudgeFrequencyOptions: [(label: String, value: Int)] = [
        ("Use Global Default", 0),
        ("Every 2 Hours", 2),
        ("Every 4 Hours", 4),
        ("Every 8 Hours", 8),
        ("Every 12 Hours", 12),
        ("Once a Day", 24),
        ("Disabled", -1)
    ]

    init(
        board: BoardGraph? = nil,
        onSave: @escaping (String, String?, String?, Int) -> Void
    ) {
        if let board {
            self.isEditing = true
            self.wasSmartBoard = board.isSmart
            _title = State(initialValue: board.title)
            _selectedIcon = State(initialValue: board.icon ?? Self.defaultIcon)
            self.preservedColorHex = board.color
            _nudgeFrequencyHours = State(initialValue: board.nudgeFrequencyHours)
        } else {
            self.isEditing = false
            self.wasSmartBoard = false
            _title = State(initialValue: "")
            _selectedIcon = State(initialValue: Self.defaultIcon)
            self.preservedColorHex = nil
            _nudgeFrequencyHours = State(initialValue: 0)
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

                Section("Nudges") {
                    Picker("Nudge Frequency", selection: $nudgeFrequencyHours) {
                        ForEach(Self.nudgeFrequencyOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .help("How often nudges can be generated for items in this board")

                    if nudgeFrequencyHours == -1 {
                        Text("Nudges are disabled for this board. Items in this board won't trigger resurfacing or streak nudges.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if wasSmartBoard {
                    Section {
                        Text("This board was previously smart. Saving now converts it to a standard board.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
        .frame(width: 420, height: 470)
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
                onSave(title, icon, preservedColorHex, nudgeFrequencyHours)
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
