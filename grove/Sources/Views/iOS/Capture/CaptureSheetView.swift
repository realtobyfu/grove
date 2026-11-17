import SwiftUI
import SwiftData

/// Capture sheet for iOS — URL/text entry with paste and board picker.
/// Presented from Library's add menu or the capture deep link.
struct CaptureSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    /// Pre-filled URL from Share Extension or deep link (grove://capture?url=)
    var prefillURL: String?
    /// Board to preselect, e.g. the Library's active board filter.
    var initialBoardID: UUID?

    @State private var urlText: String = ""
    @State private var selectedBoardID: UUID?
    @State private var isSaving = false

    private var canSave: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - URL input
                Section {
                    HStack {
                        TextField(
                            "URL or text",
                            text: $urlText,
                            prompt: Text("Paste a URL or type a note")
                                .font(.groveBody)
                                .foregroundStyle(Color.textMuted)
                        )
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
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
                                .font(.groveBody)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textSecondary)
                                .frame(minWidth: LayoutDimensions.minTouchTarget,
                                       minHeight: LayoutDimensions.minTouchTarget)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Paste from clipboard")
                    }
                } header: {
                    Text("Link or Text")
                        .sectionHeaderStyle()
                }
                .listRowBackground(Color.bgCard)

                // MARK: - Board picker
                Section {
                    Picker(selection: $selectedBoardID) {
                        Text("None (Inbox)")
                            .font(.groveBody)
                            .tag(UUID?.none)
                        ForEach(boards) { board in
                            Label {
                                Text(board.title)
                                    .font(.groveBody)
                            } icon: {
                                Image(systemName: board.icon ?? "folder")
                            }
                            .tag(Optional(board.id))
                        }
                    } label: {
                        Text("Board")
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                    }
                } header: {
                    Text("Add to Board")
                        .sectionHeaderStyle()
                } footer: {
                    Text("Without a board, it lands in Today's inbox.")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.bgCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle("Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Capture")
                        .font(.groveListTitle)
                        .foregroundStyle(Color.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.groveBody)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .font(.groveBodyMedium)
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let prefillURL, !prefillURL.isEmpty, urlText.isEmpty {
                    urlText = prefillURL
                }
                if selectedBoardID == nil, let initialBoardID,
                   boards.contains(where: { $0.id == initialBoardID }) {
                    selectedBoardID = initialBoardID
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
        let board = selectedBoardID.flatMap { boardID in
            boards.first(where: { $0.id == boardID })
        }
        _ = captureService.captureItem(input: trimmed, board: board)

        dismiss()
    }
}
