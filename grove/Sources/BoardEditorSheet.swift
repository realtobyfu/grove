import SwiftUI
import SwiftData

struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allTags: [Tag]

    @State var title: String
    @State var selectedIcon: String
    @State var selectedColorHex: String
    @State var isSmart: Bool
    @State var smartRuleLogic: SmartRuleLogic
    @State var selectedRuleTagIDs: Set<UUID>
    @State var tagSearchText: String = ""

    let isEditing: Bool
    let onSave: (String, String?, String?) -> Void
    let onSaveSmart: ((String, String?, String?, [Tag], SmartRuleLogic) -> Void)?

    private static let defaultIcon = "folder"
    private static let defaultColor = "007AFF"

    init(board: Board? = nil,
         onSave: @escaping (String, String?, String?) -> Void,
         onSaveSmart: ((String, String?, String?, [Tag], SmartRuleLogic) -> Void)? = nil) {
        if let board {
            self.isEditing = true
            _title = State(initialValue: board.title)
            _selectedIcon = State(initialValue: board.icon ?? Self.defaultIcon)
            _selectedColorHex = State(initialValue: board.color ?? Self.defaultColor)
            _isSmart = State(initialValue: board.isSmart)
            _smartRuleLogic = State(initialValue: board.smartRuleLogic)
            _selectedRuleTagIDs = State(initialValue: Set(board.smartRuleTags.map(\.id)))
        } else {
            self.isEditing = false
            _title = State(initialValue: "")
            _selectedIcon = State(initialValue: Self.defaultIcon)
            _selectedColorHex = State(initialValue: Self.defaultColor)
            _isSmart = State(initialValue: false)
            _smartRuleLogic = State(initialValue: .or)
            _selectedRuleTagIDs = State(initialValue: [])
        }
        self.onSave = onSave
        self.onSaveSmart = onSaveSmart
    }

    private var filteredTags: [Tag] {
        let sorted = allTags.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        if tagSearchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(tagSearchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Board Name") {
                    TextField("Enter board name", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Icon") {
                    iconPicker
                }

                Section("Color") {
                    colorPicker
                }

                Section {
                    Toggle("Smart Board", isOn: $isSmart.animation(.easeInOut(duration: 0.2)))
                        .help("Smart boards auto-populate based on tag rules")
                }

                if isSmart {
                    Section("Tag Rules") {
                        smartBoardRules
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
        .frame(width: 420, height: isSmart ? 680 : 480)
        .animation(.easeInOut(duration: 0.2), value: isSmart)
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Board" : "New Board")
                .font(.headline)
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
                if isSmart, let onSaveSmart {
                    let selectedTags = allTags.filter { selectedRuleTagIDs.contains($0.id) }
                    onSaveSmart(title, icon, color, selectedTags, smartRuleLogic)
                } else {
                    onSave(title, icon, color)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (isSmart && selectedRuleTagIDs.isEmpty))
        }
        .padding()
    }

    // MARK: - Smart Board Rules

    private var smartBoardRules: some View {
        VStack(alignment: .leading, spacing: 10) {
            // AND/OR logic picker
            Picker("Logic", selection: $smartRuleLogic) {
                ForEach(SmartRuleLogic.allCases, id: \.self) { logic in
                    Text(logic.displayName).tag(logic)
                }
            }
            .pickerStyle(.segmented)

            Text(smartRuleLogic.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Selected tags
            if !selectedRuleTagIDs.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(allTags.filter({ selectedRuleTagIDs.contains($0.id) })) { tag in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(tag.category.color)
                                .frame(width: 5, height: 5)
                            Text(tag.name)
                                .font(.caption2)
                            Button {
                                selectedRuleTagIDs.remove(tag.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(tag.category.color.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                Divider()
            }

            // Tag search
            TextField("Search tags...", text: $tagSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            // Available tags list
            if !filteredTags.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredTags) { tag in
                            let isSelected = selectedRuleTagIDs.contains(tag.id)
                            Button {
                                if isSelected {
                                    selectedRuleTagIDs.remove(tag.id)
                                } else {
                                    selectedRuleTagIDs.insert(tag.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(isSelected ? tag.category.color : .secondary)
                                    Circle()
                                        .fill(tag.category.color)
                                        .frame(width: 6, height: 6)
                                    Text(tag.name)
                                        .font(.caption)
                                    Spacer()
                                    Text(tag.category.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if allTags.isEmpty {
                Text("No tags available. Create tags on items first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isSmart && selectedRuleTagIDs.isEmpty {
                Text("Select at least one tag for the smart board rule.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Icon Picker

    private static let iconOptions: [String] = [
        "folder", "book", "laptopcomputer", "brain",
        "lightbulb", "star", "heart", "hammer",
        "paintbrush", "music.note", "globe", "atom",
        "function", "terminal", "cpu", "network",
        "chart.bar", "doc.text", "photo", "film",
        "gamecontroller", "graduationcap", "flask", "wrench",
        "leaf", "bolt", "eye", "hand.raised",
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
                        .frame(width: 32, height: 32)
                        .background(
                            selectedIcon == icon
                                ? Color.accentColor.opacity(0.2)
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
                        .frame(width: 28, height: 28)
                        .overlay(
                            selectedColorHex == hex
                                ? Circle().stroke(Color.primary, lineWidth: 2)
                                : nil
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
        }
    }
}
