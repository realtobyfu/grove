import SwiftUI

struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColorHex: String
    @State private var nudgeFrequencyHours: Int

    private let isEditing: Bool
    private let wasSmartBoard: Bool
    private let onSave: (String, String?, String?, Int) -> Void

    private static let defaultIcon = "folder"
    private static let defaultColor = "007AFF"

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
        board: Board? = nil,
        onSave: @escaping (String, String?, String?, Int) -> Void
    ) {
        if let board {
            self.isEditing = true
            self.wasSmartBoard = board.isSmart
            _title = State(initialValue: board.title)
            _selectedIcon = State(initialValue: board.icon ?? Self.defaultIcon)
            _selectedColorHex = State(initialValue: board.color ?? Self.defaultColor)
            _nudgeFrequencyHours = State(initialValue: board.nudgeFrequencyHours)
        } else {
            self.isEditing = false
            self.wasSmartBoard = false
            _title = State(initialValue: "")
            _selectedIcon = State(initialValue: Self.defaultIcon)
            _selectedColorHex = State(initialValue: Self.defaultColor)
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

                Section("Color") {
                    colorPicker
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
        .frame(width: 420, height: 540)
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
                let color = selectedColorHex.isEmpty ? nil : selectedColorHex
                onSave(title, icon, color, nudgeFrequencyHours)
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

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
            ForEach(Self.iconOptions, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: selectedColorHex))
                        .frame(width: 32, height: 32)
                        .background(
                            selectedIcon == icon
                                ? Color.accentBadge
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Color Picker

    private static let colorOptions: [String] = [
        "007AFF", "34C759", "FF3B30", "FF9500",
        "AF52DE", "FF2D55", "5856D6", "00C7BE",
        "A2845E", "8E8E93", "FFD60A", "64D2FF"
    ]

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
            ForEach(Self.colorOptions, id: \.self) { hex in
                Button {
                    selectedColorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(selectedColorHex == hex ? 1 : 0), lineWidth: 2)
                        )
                        .padding(4)
                        .background(
                            selectedColorHex == hex
                                ? Color.accentBadge
                                : Color.clear
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }
}
