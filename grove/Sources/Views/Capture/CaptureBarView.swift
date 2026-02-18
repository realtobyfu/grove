import SwiftUI
import SwiftData

struct CaptureBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var inputText = ""
    @State private var showConfirmation = false
    @FocusState private var isFocused: Bool

    /// Currently selected board (passed from ContentView)
    var currentBoardID: UUID?

    private var isURL: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else { return false }
        return true
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isURL ? "link" : "note.text")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 16)

            TextField("", text: $inputText, prompt:
                Text("Paste a URL or type a note...")
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.groveBody)
            .foregroundStyle(Color.textPrimary)
            .focused($isFocused)
            .onSubmit {
                capture()
            }

            if !inputText.isEmpty {
                Button {
                    capture()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text("⏎")
                .font(.groveShortcut)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.borderPrimary : Color.borderInput, lineWidth: 1)
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .overlay {
            if showConfirmation {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.groveBody)
                    Text("Captured")
                        .font(.groveBodySmall)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.bgCard)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    private func capture() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let viewModel = ItemViewModel(modelContext: modelContext)
        let item = viewModel.captureItem(input: trimmed)

        // Auto-assign to current board if one is selected
        if let boardID = currentBoardID,
           let board = boards.first(where: { $0.id == boardID }) {
            viewModel.assignToBoard(item, board: board)
        }

        inputText = ""

        // Flash confirmation
        withAnimation(.easeIn(duration: 0.15)) {
            showConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showConfirmation = false
            }
        }
    }
}
