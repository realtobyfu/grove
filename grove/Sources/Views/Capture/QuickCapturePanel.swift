import SwiftUI
import SwiftData

struct QuickCapturePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "leaf")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textSecondary)
                Text("Quick Capture")
                    .font(.groveBodyMedium)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            TextField("Paste a URL or type a note…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.groveBody)
                .padding(Spacing.sm)
                .background(Color.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderInput, lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit {
                    capture()
                }

            HStack {
                if !inputText.isEmpty {
                    let isURL = detectIsURL(inputText)
                    Image(systemName: isURL ? "link" : "note.text")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                    Text(isURL ? "Will save as \(isVideoURL(inputText) ? "video" : "article")" : "Will save as note")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text("⏎ to capture")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 400)
        .onAppear {
            isFocused = true
        }
    }

    private func capture() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let viewModel = ItemViewModel(modelContext: modelContext)
        _ = viewModel.captureItem(input: trimmed)

        inputText = ""
        dismiss()
    }

    private func detectIsURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else { return false }
        return true
    }

    private func isVideoURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("youtube.com/watch")
            || lower.contains("youtu.be/")
            || lower.contains("vimeo.com/")
    }
}
