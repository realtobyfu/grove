import SwiftUI

/// "Continue" in Today's Yours column: the notes most recently worked on, each
/// one click from its page, and a way to start another.
struct HomeContinueSection: View {
    let notes: [Item]
    let onOpen: (Item) -> Void
    let onNewNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodaySectionHeader(
                title: "Continue",
                badge: notes.isEmpty ? nil : "\(notes.count)"
            )

            if notes.isEmpty {
                GroveEmptyState(
                    title: "Nothing in progress",
                    detail: "A note you are writing is picked up again here."
                )
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(notes, id: \.id) { note in
                        ContinueNoteEntry(note: note, action: { onOpen(note) })
                    }
                }
            }

            Button(action: onNewNote) {
                KeyHintLabel(title: "New note", key: "\u{2318}\u{21E7}N")
            }
            .buttonStyle(.grove(.secondary, size: .compact))
            .padding(.top, Spacing.sm)
            .help("Start a new note")
        }
    }
}

// MARK: - Note Entry

/// One note under "Continue": its title, the first line that says something,
/// and when it was last edited.
private struct ContinueNoteEntry: View {
    let note: Item
    let action: () -> Void

    private var snippet: String? {
        TodayDigest.snippet(from: note.content)
    }

    /// "Edited 2 hours ago · 108 words". The word count is left off an empty note.
    private var editedLine: String {
        let edited = "Edited \(note.updatedAt.formatted(.relative(presentation: .named)))"
        guard let words = TodayDigest.wordCountLabel(for: note.content) else { return edited }
        return "\(edited) \u{00B7} \(words)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(note.title)
                    .font(.groveBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if let snippet {
                    Text(snippet)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(editedLine)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .entryStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(note.title)")
    }
}
