import SwiftUI
import SQLiteData

struct LearningFocusView: View {
    @Environment(\.dismiss) private var dismiss
    @FetchAll(Board.order(by: \.sortOrder)) private var boards
    @State private var boardIDs: Set<UUID> = []
    @State private var minutes = 3
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Text("Select boards, or leave all unselected to review your library.")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                ForEach(boards) { board in
                    Toggle(isOn: Binding(get: { boardIDs.contains(board.id) }, set: { selected in
                        if selected { boardIDs.insert(board.id) } else { boardIDs.remove(board.id) }
                    })) {
                        Label(board.title, systemImage: board.icon ?? "folder")
                    }
                    .tint(Color.textPrimary)
                }
            } header: { Text("Boards") }
            Section {
                Picker("Session length", selection: $minutes) {
                    Text("1 minute").tag(1)
                    Text("3 minutes").tag(3)
                    Text("5 minutes").tag(5)
                }
                .pickerStyle(.segmented)
                Text("Approximate length; stop anytime.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
            } header: { Text("Session") }
            if let errorMessage { Text(errorMessage).font(.groveBodySmall) }
            Button("Save focus", action: save)
                .buttonStyle(LearningPrimaryButtonStyle())
        }
        .navigationTitle("Your focus")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let prefs = LearningService().preferences()
            boardIDs = Set(prefs.focusBoardIDs)
            minutes = prefs.sessionMinutes
        }
    }

    private func save() {
        let service = LearningService()
        var prefs = service.preferences()
        prefs.focusBoardIDs = Array(boardIDs).sorted { $0.uuidString < $1.uuidString }
        prefs.sessionMinutes = minutes
        do {
            try service.savePreferences(prefs)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
