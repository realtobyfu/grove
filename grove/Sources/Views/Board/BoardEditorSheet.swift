import SwiftUI

struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedIcon: String

    private let isEditing: Bool
    private let onSave: (String, String?) -> Void

    private static let defaultIcon = "folder"

    init(
        board: Board? = nil,
        onSave: @escaping (String, String?) -> Void
    ) {
        if let board {
            self.isEditing = true
            _title = State(initialValue: board.title)
            _selectedIcon = State(initialValue: board.icon ?? Self.defaultIcon)
        } else {
            self.isEditing = false
            _title = State(initialValue: "")
            _selectedIcon = State(initialValue: Self.defaultIcon)
        }
        self.onSave = onSave
    }

    var body: some View {
        #if os(macOS)
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
        #else
        NavigationStack {
            Form {
                Section("Board Name") {
                    TextField("Enter board name", text: $title)
                        .font(.groveBody)
                }

                Section("Icon") {
                    iconPicker
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle(isEditing ? "Edit Board" : "New Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
        }
        .presentationDetents([.medium, .large])
        #endif
    }

    #if os(macOS)
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

            confirmButton
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    #endif

    private var confirmButton: some View {
        Button(isEditing ? "Save" : "Create") {
            let icon = selectedIcon.isEmpty ? nil : selectedIcon
            onSave(title, icon)
            dismiss()
        }
        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
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

    #if os(macOS)
    private let iconCellSize: CGFloat = 32
    private let iconGridSpacing: CGFloat = 8
    private let iconColumns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8)
    #else
    /// Fills whatever width the sheet gives it, at the 44pt touch minimum.
    private let iconCellSize = LayoutDimensions.minTouchTarget
    private let iconGridSpacing: CGFloat = 4
    private let iconColumns = [GridItem(.adaptive(minimum: LayoutDimensions.minTouchTarget), spacing: 4)]
    #endif

    /// Icons read in ink, never in color. The selected one steps up to full
    /// ink inside a 3pt-radius outline — the same weight-and-rule hierarchy
    /// the rest of the app uses instead of a tint.
    private var iconPicker: some View {
        LazyVGrid(columns: iconColumns, spacing: iconGridSpacing) {
            ForEach(Self.iconOptions, id: \.self) { icon in
                let isSelected = selectedIcon == icon
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                        .frame(width: iconCellSize, height: iconCellSize)
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
