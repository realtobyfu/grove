import SwiftUI

struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedIcon: String
    /// Bare hex from `BoardColor`, or `nil` for a plain ink icon.
    @State private var selectedColorHex: String?

    private let isEditing: Bool
    /// The colour the board had when the sheet opened, so a colour from
    /// outside the palette stays on offer while other swatches are tried.
    private let originalColorHex: String?
    /// Title, icon, colour.
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
            let colorHex = BoardColor.normalized(board.color)
            self.originalColorHex = colorHex
            _selectedColorHex = State(initialValue: colorHex)
        } else {
            self.isEditing = false
            _title = State(initialValue: "")
            _selectedIcon = State(initialValue: Self.defaultIcon)
            self.originalColorHex = nil
            _selectedColorHex = State(initialValue: nil)
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

                Section("Color") {
                    colorPicker
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
        .frame(width: 420, height: 500)
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

                Section("Color") {
                    colorPicker
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
            onSave(title, icon, selectedColorHex)
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
    private let iconColumns = Array(repeating: GridItem(.fixed(36), spacing: Spacing.sm), count: 8)
    #else
    /// Fills whatever width the sheet gives it, at the 44pt touch minimum.
    private let iconCellSize = LayoutDimensions.minTouchTarget
    private let iconGridSpacing: CGFloat = 4
    private let iconColumns = [GridItem(.adaptive(minimum: LayoutDimensions.minTouchTarget), spacing: Spacing.xs)]
    #endif

    /// The selected icon steps up inside a 3pt-radius outline — the same
    /// weight-and-rule hierarchy the rest of the app uses — and previews the
    /// board's colour; the others stay in secondary ink.
    private var iconPicker: some View {
        LazyVGrid(columns: iconColumns, spacing: iconGridSpacing) {
            ForEach(Self.iconOptions, id: \.self) { icon in
                let isSelected = selectedIcon == icon
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? (selectedTint ?? Color.textPrimary) : Color.textSecondary)
                        .frame(width: iconCellSize, height: iconCellSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.tag)
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

    // MARK: - Color Picker

    private var selectedTint: Color? {
        BoardColor.color(for: selectedColorHex)
    }

    /// The palette, plus the colour the board came in with when it isn't one
    /// of the palette's (an imported board, say), so it can always be put back.
    private var colorOptions: [BoardColor.Option] {
        guard let originalColorHex,
              !BoardColor.options.contains(where: { $0.hex == originalColorHex }) else {
            return BoardColor.options
        }
        return BoardColor.options + [BoardColor.Option(hex: originalColorHex, name: "Custom")]
    }

    /// "None" first — plain ink, and what a new board starts with — then the
    /// swatches. Selection uses the icon picker's outline.
    private var colorPicker: some View {
        LazyVGrid(columns: iconColumns, spacing: iconGridSpacing) {
            colorCell(name: "None", isSelected: selectedColorHex == nil) {
                selectedColorHex = nil
            } swatch: {
                Image(systemName: "circle.slash")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }

            ForEach(colorOptions) { option in
                colorCell(name: option.name, isSelected: selectedColorHex == option.hex) {
                    selectedColorHex = option.hex
                } swatch: {
                    Circle()
                        .fill(BoardColor.color(for: option.hex) ?? Color.textSecondary)
                        .frame(width: 16, height: 16)
                }
            }
        }
    }

    private func colorCell<Swatch: View>(
        name: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder swatch: () -> Swatch
    ) -> some View {
        Button(action: action) {
            swatch()
                .frame(width: iconCellSize, height: iconCellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.tag)
                        .stroke(Color.textPrimary, lineWidth: isSelected ? 1 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
