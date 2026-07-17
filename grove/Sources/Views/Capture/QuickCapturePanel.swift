import SwiftUI
import SwiftData

struct QuickCapturePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @FocusState private var isFocused: Bool

    private var trimmedInput: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validLink: String? {
        normalizedLink(from: linkText)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.and.pencil")
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
                .accessibilityLabel("Close quick capture")
                .accessibilityHint("Dismisses the quick capture window.")
            }

            HStack(spacing: Spacing.sm) {
                TextField("Paste a link or jot a note", text: $linkText)
                    .textFieldStyle(.plain)
                    .font(.groveBody)
                    .focused($isFocused)
                    .onSubmit {
                        capture()
                    }

                Button {
                    capture()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.groveBody)
                        .foregroundStyle(trimmedInput.isEmpty ? Color.textTertiary : Color.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(trimmedInput.isEmpty)
                .accessibilityLabel("Capture")
            }
            .padding(Spacing.sm)
            .background(Color.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderInput, lineWidth: 1)
            )

            Text("Press Return to capture. Links become articles, everything else a note.")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Spacing.lg)
        .frame(width: 420)
        .onAppear {
            isFocused = true
        }
    }

    private func capture() {
        guard !trimmedInput.isEmpty else { return }

        // URL fast path: normalized http(s) links capture exactly as before;
        // anything else is saved as a note.
        let input = validLink ?? trimmedInput
        let captureService = CaptureService(modelContext: modelContext)
        _ = captureService.captureItemDetailed(input: input)

        linkText = ""
        dismiss()
    }

    private func normalizedLink(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = validHTTPURL(trimmed) {
            return direct.absoluteString
        }
        if !trimmed.contains("://"), let prefixed = validHTTPURL("https://\(trimmed)") {
            return prefixed.absoluteString
        }
        return nil
    }

    private func validHTTPURL(_ raw: String) -> URL? {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        return url
    }
}
