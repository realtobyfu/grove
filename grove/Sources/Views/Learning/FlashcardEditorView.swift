import SwiftUI
import SwiftData

/// Works in a presentation or inside the desktop's existing contextual rail.
struct FlashcardEditorView: View {
    var item: Item? = nil
    var reflection: ReflectionBlock? = nil
    var card: Flashcard? = nil
    var sourceQuote: String? = nil
    var onSaved: (() -> Void)? = nil
    var isEmbedded = false
    var boardID: UUID? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var hints = ""
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var suggestionRequest: UUID?
    @State private var isSuggesting = false
    @State private var suggestedDraft: FlashcardDraft?
    @State private var suggestionError: String?

    private var quote: String? {
        card?.sourceQuote ?? sourceQuote ?? reflection?.highlight ?? reflection?.content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let quote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("SOURCE")
                        .sectionHeaderStyle()
                    Text(quote)
                        .font(.groveSerif)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, Spacing.md)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.borderInput).frame(width: 2)
                        }
                }

                if let quote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        isSuggesting = true
                        suggestedDraft = nil
                        suggestionError = nil
                        suggestionRequest = UUID()
                    } label: {
                        HStack {
                            if isSuggesting { ProgressView().controlSize(.small) }
                            Text(isSuggesting ? "Suggesting…" : "Suggest a question")
                        }
                    }
                    .buttonStyle(LearningSecondaryButtonStyle())
                    .disabled(isSuggesting)
                    Text("AI uses this passage to draft a card. Review it before saving.")
                        .font(.groveBodySmall).foregroundStyle(Color.textTertiary)
                }
                if let suggestedDraft {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("DRAFT").sectionHeaderStyle()
                        Text(suggestedDraft.question).font(.groveItemTitle)
                        Text(suggestedDraft.answer).font(.groveBodySmall).foregroundStyle(Color.textSecondary)
                        Button("Use draft") {
                            question = suggestedDraft.question
                            answer = suggestedDraft.answer
                            hints = suggestedDraft.hints.joined(separator: "\n")
                            self.suggestedDraft = nil
                        }.buttonStyle(LearningSecondaryButtonStyle())
                        Button("Dismiss draft") { self.suggestedDraft = nil }
                            .buttonStyle(.plain).frame(minHeight: 44)
                    }
                }
                if let suggestionError {
                    Text(suggestionError).font(.groveBodySmall).foregroundStyle(Color.textSecondary)
                }

                field("Question", text: $question, prompt: "One specific question…", lines: 2...5)
                field("Answer", text: $answer, prompt: "In your own words…", lines: 3...8)
                field("Hints (optional)", text: $hints, prompt: "One cue per line, without the answer…", lines: 2...5)

                if let title = card?.sourceTitle ?? item?.title, !title.isEmpty {
                    Label(title, systemImage: "doc.text")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let item, !item.boards.isEmpty {
                    Label(item.boards.map(\.title).joined(separator: ", "), systemImage: "folder")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityLabel("Could not save: \(errorMessage)")
                }
                Button(card == nil ? "Save flashcard" : "Save changes", action: save)
                    .buttonStyle(LearningPrimaryButtonStyle())
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Spacing.lg)
        }
        .background(Color.bgPrimary)
        .modifier(LearningEditorTitle(isEmbedded: isEmbedded, title: card == nil ? "New flashcard" : "Edit flashcard"))
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: load)
        .task(id: suggestionRequest) {
            guard let request = suggestionRequest, let passage = quote else { return }
            let title = card?.sourceTitle ?? item?.title ?? "Your passage"
            let service = FlashcardDraftService()
            let draft = await service.generateDraft(sourceTitle: title, sourceQuote: passage)
            guard !Task.isCancelled, suggestionRequest == request else { return }
            suggestedDraft = draft
            suggestionError = draft == nil ? service.lastError : nil
            isSuggesting = false
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased()).sectionHeaderStyle()
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(lines)
                .font(.groveBody)
                .textFieldStyle(.plain)
                .padding(Spacing.md)
                .background(Color.bgCard)
                .clipShape(.rect(cornerRadius: LayoutDimensions.cardCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                        .stroke(Color.borderInput, lineWidth: 1)
                }
                .accessibilityLabel(title)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        question = card?.question ?? ""
        answer = card?.answer ?? reflection?.content ?? sourceQuote ?? ""
        hints = card?.hints.joined(separator: "\n") ?? ""
    }

    private func save() {
        let cueLines = hints.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let service = LearningService(modelContext: modelContext)
        do {
            if let card {
                try service.updateCard(card, question: question, answer: answer, hints: cueLines)
            } else {
                let newCard = Flashcard(question: question, answer: answer, sourceItem: item,
                                        sourceQuote: quote, sourceReflectionID: reflection?.id, hints: cueLines)
                if let boardID, !newCard.boardIDs.contains(boardID) { newCard.boardIDs.append(boardID) }
                if let timestamp = reflection?.videoTimestamp { newCard.sourceLocator = "video:\(timestamp)" }
                try service.saveCard(newCard)
                item?.promoteFromFeedSuggestionIfNeeded()
                try modelContext.save()
            }
            onSaved?()
            if !isEmbedded { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LearningEditorTitle: ViewModifier {
    var isEmbedded: Bool
    var title: String
    @ViewBuilder func body(content: Content) -> some View {
        if isEmbedded { content } else { content.navigationTitle(title) }
    }
}
