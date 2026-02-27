import SwiftUI
import SwiftData

/// Inline "Paste a URL or type a note..." capture bar matching the Mac app's always-visible input.
/// Used at the top of Home view and as the iPad capture surface.
struct InlineCaptureBar: View {
    @Environment(\.modelContext) private var modelContext
    @State private var inputText = ""
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var selectedBoardID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textMuted)

                TextField("Paste a URL or type a note...", text: $inputText)
                    .font(.groveBody)
                    .focused($isFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { save() }

                if !inputText.isEmpty {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "return")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .frame(minWidth: LayoutDimensions.minTouchTarget,
                           minHeight: LayoutDimensions.minTouchTarget)
                } else {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(minWidth: LayoutDimensions.minTouchTarget,
                           minHeight: LayoutDimensions.minTouchTarget)
                    .accessibilityLabel("Paste from clipboard")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                    .stroke(Color.borderInput, lineWidth: 1)
            }
        }
        .listRowInsets(EdgeInsets(top: Spacing.sm, leading: LayoutDimensions.contentPaddingH, bottom: Spacing.sm, trailing: LayoutDimensions.contentPaddingH))
        .listRowSeparator(.hidden)
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let string = UIPasteboard.general.string {
            inputText = string
            isFocused = true
        }
        #endif
    }

    private func save() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let captureService = CaptureService(modelContext: modelContext)
        _ = captureService.captureItem(input: trimmed)

        inputText = ""
        isFocused = false
    }
}
