import SwiftUI
import SwiftData

struct FlashcardLibraryView: View {
    var boardID: UUID? = nil
    var itemID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flashcard.updatedAt, order: .reverse) private var allCards: [Flashcard]
    @Query private var items: [Item]
    @State private var editor: LearningEditorSession?
    @State private var showReview = false
    @State private var errorMessage: String?
    @State private var cardToDelete: Flashcard?
    @State private var showDeleteConfirmation = false

    private var cards: [Flashcard] {
        allCards.filter { card in
            guard card.deletedAt == nil else { return false }
            if let boardID, !card.boardIDs.contains(boardID) { return false }
            if let itemID, card.sourceItemID != itemID { return false }
            return true
        }
    }

    var body: some View {
        List {
            if let errorMessage { Text(errorMessage).font(.groveBodySmall) }
            if cards.isEmpty {
                ContentUnavailableView("No flashcards", systemImage: "rectangle.on.rectangle", description: Text("Create one here or from a passage, reflection, or note."))
            }
            ForEach(cards) { card in
                Button {
                    editor = LearningEditorSession(card: card)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(card.question).font(.groveItemTitle)
                        Text(card.sourceTitle.isEmpty ? "Your question" : card.sourceTitle)
                            .font(.groveMeta).foregroundStyle(Color.textTertiary)
                        Text(card.isSuspended ? "Paused" : card.dueAt <= .now ? "Ready to review" : "Next review \(card.dueAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.groveBodySmall).foregroundStyle(Color.textSecondary)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit") { editor = LearningEditorSession(card: card) }
                    Button(card.isSuspended ? "Resume reviews" : "Pause reviews") { togglePause(card) }
                    Button("Delete flashcard", role: .destructive) {
                        cardToDelete = card
                        showDeleteConfirmation = true
                    }
                }
                .swipeActions {
                    Button(card.isSuspended ? "Resume" : "Pause") { togglePause(card) }
                        .tint(Color.textPrimary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Flashcards")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Review", systemImage: "play") { showReview = true }
                Button("New flashcard", systemImage: "plus") {
                    editor = LearningEditorSession(item: items.first { $0.id == itemID }, boardID: boardID)
                }
            }
        }
        .confirmationDialog("Delete this flashcard?", isPresented: $showDeleteConfirmation, titleVisibility: .visible, presenting: cardToDelete) { card in
            Button("Delete flashcard", role: .destructive) { delete(card) }
            Button("Cancel", role: .cancel) { cardToDelete = nil }
        } message: { card in
            Text("Removes “\(card.question)” from all synced devices. Keeps the source.")
        }
        .sheet(item: $editor) { value in
            NavigationStack {
                FlashcardEditorView(item: value.item, reflection: value.reflection, card: value.card, sourceQuote: value.sourceQuote, boardID: value.boardID)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
        }
        .sheet(isPresented: $showReview) {
            NavigationStack { LearningReviewView(boardID: boardID, itemID: itemID) }
            #if os(macOS)
            .frame(width: 680, height: 500)
            #endif
        }
    }

    private func delete(_ card: Flashcard) {
        let previousDeletedAt = card.deletedAt
        let previousSuspension = card.isSuspended
        let previousUpdatedAt = card.updatedAt
        do {
            try LearningService(modelContext: modelContext).deleteCard(card)
            cardToDelete = nil
            errorMessage = nil
        } catch {
            card.deletedAt = previousDeletedAt
            card.isSuspended = previousSuspension
            card.updatedAt = previousUpdatedAt
            errorMessage = error.localizedDescription
        }
    }

    private func togglePause(_ card: Flashcard) {
        let wasSuspended = card.isSuspended
        card.isSuspended.toggle()
        do { try LearningService(modelContext: modelContext).saveCard(card) }
        catch { card.isSuspended = wasSuspended; errorMessage = error.localizedDescription }
    }
}
