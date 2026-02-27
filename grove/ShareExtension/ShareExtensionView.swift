import SwiftUI
import SwiftData

/// SwiftUI view for the Share Extension — shows a preview of the shared
/// content (title + domain), a board picker from the shared store, an
/// optional note field, and Save/Cancel toolbar buttons.
///
/// The view writes directly to the shared ModelContainer (App Group).
/// Heavy processing (metadata fetch, auto-tagging, overview generation)
/// is deferred to the main app's next launch to stay within the
/// extension's 120 MB memory limit.
struct ShareExtensionView: View {
    let sharedURL: String
    let sharedTitle: String?
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var noteText = ""
    @State private var selectedBoardID: UUID?
    @State private var isSaving = false

    private var displayTitle: String {
        if let title = sharedTitle, !title.isEmpty {
            return title
        }
        return sharedURL
    }

    private var domain: String? {
        guard let url = URL(string: sharedURL),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var isURL: Bool {
        URL(string: sharedURL)?.scheme?.lowercased().hasPrefix("http") == true
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                boardPickerSection
                noteSection
            }
            .navigationTitle("Save to Grove")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let domain {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption)
                        Text(domain)
                            .font(.subheadline.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Saving to Grove")
        }
    }

    private var boardPickerSection: some View {
        Section {
            Picker("Board", selection: $selectedBoardID) {
                Text("None (Inbox)")
                    .tag(UUID?.none)
                ForEach(boards.filter { !$0.isSmart }) { board in
                    Label(board.title, systemImage: board.icon ?? "folder")
                        .tag(Optional(board.id))
                }
            }
        } header: {
            Text("Add to Board")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Add a note...", text: $noteText, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Note")
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true

        let item = Item(
            title: sharedTitle ?? (isURL ? sharedURL : String(sharedURL.prefix(80))),
            type: isURL ? .article : .note
        )
        item.status = .inbox

        if isURL {
            item.sourceURL = sharedURL
        } else {
            item.content = sharedURL
        }

        // Mark as needing metadata fetch so the main app picks it up
        if isURL {
            item.metadata["fetchingMetadata"] = "true"
            item.metadata["pendingFromExtension"] = "true"
        }

        // Append note if provided
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            let existing = item.content ?? ""
            item.content = existing.isEmpty ? trimmedNote : existing + "\n\n---\n" + trimmedNote
        }

        modelContext.insert(item)

        // Assign to board if selected
        if let boardID = selectedBoardID,
           let board = boards.first(where: { $0.id == boardID }) {
            item.boards.append(board)
        }

        try? modelContext.save()
        onComplete()
    }
}
