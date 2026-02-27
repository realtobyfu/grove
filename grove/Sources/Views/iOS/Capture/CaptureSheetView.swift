import SwiftUI
import SwiftData

/// Capture sheet for iOS — URL/text entry with paste and board picker.
/// Presented as a .sheet from FloatingCaptureButton or deep link.
struct CaptureSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    /// Pre-filled URL from Share Extension or deep link (grove://capture?url=)
    var prefillURL: String?

    @State private var urlText: String = ""
    @State private var selectedBoardID: UUID?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - URL input
                Section {
                    HStack {
                        TextField("URL or text", text: $urlText)
                            .textContentType(.URL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()

                        Button {
                            pasteFromClipboard()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: LayoutDimensions.minTouchTarget,
                               minHeight: LayoutDimensions.minTouchTarget)
                        .accessibilityLabel("Paste from clipboard")
                    }
                } header: {
                    Text("Link or Text")
                        .sectionHeaderStyle()
                }

                // MARK: - Board picker
                Section {
                    Picker("Board", selection: $selectedBoardID) {
                        Text("None (Inbox)")
                            .tag(UUID?.none)
                        ForEach(boards) { board in
                            Label(board.title, systemImage: board.icon ?? "folder")
                                .tag(Optional(board.id))
                        }
                    }
                } header: {
                    Text("Add to Board")
                        .sectionHeaderStyle()
                }

            }
            .navigationTitle("Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let prefillURL, !prefillURL.isEmpty {
                    urlText = prefillURL
                }
            }
        }
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        #if os(iOS)
        if let string = UIPasteboard.general.string {
            urlText = string
        }
        #endif
    }

    private func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true

        let captureService = CaptureService(modelContext: modelContext)
        let item = captureService.captureItem(input: trimmed)

        // Assign to selected board if chosen
        if let boardID = selectedBoardID,
           let board = boards.first(where: { $0.id == boardID }) {
            let viewModel = ItemViewModel(modelContext: modelContext)
            viewModel.assignToBoard(item, board: board)
        }

        dismiss()
    }
}
