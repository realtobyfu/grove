import SwiftUI
import SwiftData

/// Session identity and source navigation stay local; durable learning is an
/// append-only review event, written only after an explicit rating.
struct LearningReviewView: View {
    var boardID: UUID? = nil
    var onOpenSource: ((Flashcard) -> Void)? = nil
    var itemID: UUID? = nil

    private enum Presentation: Identifiable {
        case source(UUID)
        case editor(UUID)
        var id: String {
            switch self {
            case .source(let id): "source-\(id)"
            case .editor(let id): "editor-\(id)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [Flashcard]
    @State private var cardIDs: [UUID] = []
    @State private var index = 0
    @State private var reviewed = 0
    @State private var supported = 0
    @State private var skipped = 0
    @State private var didLoad = false
    @State private var isFinished = false
    @State private var revealed = false
    @State private var hintCount = 0
    @State private var usedHint = false
    @State private var readSource = false
    @State private var showSourcePane = false
    @State private var availableWidth: CGFloat = 0
    @State private var presentation: Presentation?
    @State private var errorMessage: String?
    @State private var sessionID = UUID()
    @State private var eventID = UUID()

    private var currentCard: Flashcard? {
        guard cardIDs.indices.contains(index) else { return nil }
        return cards.first { $0.id == cardIDs[index] && $0.deletedAt == nil && !$0.isSuspended }
    }

    private var reviewShortcutsEnabled: Bool { !showSourcePane && presentation == nil && !isFinished }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                reviewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showSourcePane, let card = currentCard {
                    Divider()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Source").font(.groveBodyMedium)
                            Spacer()
                            Button("Close", systemImage: "xmark") { showSourcePane = false }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .padding(.horizontal, Spacing.lg)
                        LearningSourcePassageView(card: card, onRetry: retry, onReadOriginal: markSourceRead, onOpenSource: onOpenSource.map { callback in
                            { card in showSourcePane = false; callback(card) }
                        })
                    }
                    .frame(width: min(380, geometry.size.width * 0.42))
                }
            }
            .onAppear { availableWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, width in
                availableWidth = width
                if width < 760, showSourcePane, let card = currentCard {
                    showSourcePane = false
                    presentation = .source(card.id)
                }
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle("Review")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isFinished || cardIDs.isEmpty ? "Done" : "Finish") {
                    dismiss()
                }
            }
        }
        .task { load() }
        .onChange(of: currentCard?.revision) { _, _ in resetAttempt() }
        .onChange(of: currentCard?.revisionFingerprint) { _, _ in resetAttempt() }
        .sheet(item: $presentation) { value in
            NavigationStack {
                switch value {
                case .source(let id):
                    if let card = cards.first(where: { $0.id == id && $0.deletedAt == nil && !$0.isSuspended }) {
                        LearningSourcePassageView(card: card, onRetry: retry, onReadOriginal: markSourceRead, onOpenSource: onOpenSource.map { callback in
                            { card in presentation = nil; callback(card) }
                        })
                        .navigationTitle("Source")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { presentation = nil } }
                        }
                    } else { unavailable }
                case .editor(let id):
                    if let card = cards.first(where: { $0.id == id && $0.deletedAt == nil && !$0.isSuspended }) {
                        FlashcardEditorView(card: card)
                    } else { unavailable }
                }
            }
            #if os(macOS)
            .frame(minWidth: 540, minHeight: 560)
            #endif
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if !didLoad {
            ProgressView("Loading…")
        } else if isFinished {
            completion
        } else if cardIDs.isEmpty {
            ContentUnavailableView("Nothing ready to review", systemImage: "checkmark.circle", description: Text("No flashcards are due in your selected focus."))
        } else if let card = currentCard {
            questionContent(card)
        } else {
            VStack(spacing: Spacing.lg) {
                unavailable
                Button("Skip") { advance(recorded: false) }
                    .buttonStyle(LearningSecondaryButtonStyle())
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView("Question unavailable", systemImage: "doc.questionmark", description: Text("This flashcard was paused or removed."))
    }

    private func questionContent(_ card: Flashcard) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Text(card.sourceTitle.isEmpty ? "Flashcard" : card.sourceTitle)
                            .lineLimit(2)
                        Spacer(minLength: Spacing.sm)
                        Text("\(index + 1) / \(cardIDs.count)")
                            .monospacedDigit()
                            .fixedSize()
                            .accessibilityLabel("Question \(index + 1) of \(cardIDs.count)")
                    }
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    Text(card.question)
                        .font(.groveTitle)
                        .textSelection(.enabled)
                        .padding(.top, Spacing.md)
                    if !revealed, hintCount > 0, !card.hints.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Hint \(hintCount) / \(card.hints.count)")
                                .font(.groveMeta).foregroundStyle(Color.textTertiary)
                            Text(card.hints[min(hintCount - 1, card.hints.count - 1)])
                                .font(.groveBody)
                        }
                        .padding(.leading, Spacing.md)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.borderInput).frame(width: 2) }
                    }
                    if revealed {
                        Divider()
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Answer").font(.groveMeta).foregroundStyle(Color.textTertiary)
                            Text(card.answer).font(.groveBody).textSelection(.enabled)
                        }
                    }
                    if let errorMessage { Text(errorMessage).font(.groveBodySmall) }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(Spacing.lg)
            }
            VStack(spacing: Spacing.sm) {
                HStack {
                    if !revealed {
                        helpActions(card)
                    } else {
                        sourceButton(card)
                        Spacer()
                        if usedHint || readSource {
                            Label("With help", systemImage: usedHint ? "lightbulb" : "book")
                                .font(.groveMeta).foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                if revealed {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                        ForEach(Array([RecallRating.again, .hard, .good, .easy].enumerated()), id: \.offset) { offset, rating in
                            ratingButton(rating, number: offset + 1, card: card)
                        }
                    }
                } else {
                    Button("Show answer") { revealed = true; showSourcePane = false }
                        .buttonStyle(LearningPrimaryButtonStyle())
                        .modifier(LearningReviewShortcut(key: .space, enabled: reviewShortcutsEnabled))
                }
                Group {
                    if revealed {
                        Button("Edit") { presentation = .editor(card.id) }
                    } else {
                        Button("Skip") { advance(recorded: false) }
                    }
                }
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.bgPrimary)
        }
    }

    private func helpActions(_ card: Flashcard) -> some View {
        HStack(spacing: Spacing.xxl) {
            if !card.hints.isEmpty { hintButton(card) }
            sourceButton(card)
            Spacer(minLength: 0)
        }
    }

    private func hintButton(_ card: Flashcard) -> some View {
        Button {
            hintCount = min(card.hints.count, hintCount + 1)
            usedHint = true
        } label: {
            Label(hintCount == 0 ? "Hint" : hintCount < card.hints.count ? "Next hint" : "Hint", systemImage: "lightbulb")
        }
        .buttonStyle(.plain)
        .font(.groveBodySmall)
        .foregroundStyle(Color.textSecondary)
        .frame(minHeight: 44)
        .disabled(card.hints.isEmpty || hintCount >= card.hints.count)
        .modifier(LearningReviewShortcut(key: "h", enabled: reviewShortcutsEnabled))
    }

    private func sourceButton(_ card: Flashcard) -> some View {
        Button(action: { openSource(card) }) { Label("Read", systemImage: "book") }
            .buttonStyle(.plain)
            .font(.groveBodySmall)
            .foregroundStyle(Color.textSecondary)
            .frame(minHeight: 44)
            .accessibilityLabel("Read source passage")
            .modifier(LearningReviewShortcut(key: "r", enabled: reviewShortcutsEnabled))
    }

    private func ratingButton(_ rating: RecallRating, number: Int, card: Flashcard) -> some View {
        Button(rating.displayName) { record(card, rating: rating) }
            .buttonStyle(LearningSecondaryButtonStyle())
            .frame(maxWidth: .infinity)
            .modifier(LearningReviewShortcut(key: KeyEquivalent(Character(String(number))), enabled: reviewShortcutsEnabled))
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Review complete")
                .font(.groveTitle)
            Text("\(reviewed) reviewed")
                .font(.groveBody).foregroundStyle(Color.textSecondary)
            if supported > 0 || skipped > 0 {
                Text([supported > 0 ? "\(supported) with help" : nil,
                      skipped > 0 ? "\(skipped) skipped" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.groveMeta).foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 480)
    }

    private func load() {
        guard !didLoad else { return }
        let service = LearningService(modelContext: modelContext)
        let due = service.dueCards(boardID: boardID).filter { itemID == nil || $0.sourceItemID == itemID }
        cardIDs = Array(due.prefix(service.preferences().sessionCardLimit)).map(\.id)
        didLoad = true
    }

    private func openSource(_ card: Flashcard) {
        if let quote = card.sourceQuote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { markSourceRead() }
        if availableWidth >= 760 { showSourcePane = true } else { presentation = .source(card.id) }
    }

    private func markSourceRead() { readSource = true }

    private func retry() {
        presentation = nil
        showSourcePane = false
        revealed = false
        hintCount = 0
    }

    private func record(_ card: Flashcard, rating: RecallRating) {
        guard currentCard?.id == card.id, revealed else { return }
        do {
            try LearningService(modelContext: modelContext).recordReview(card: card, rating: rating, usedHint: usedHint,
                readSource: readSource, sessionID: sessionID, eventID: eventID)
            if usedHint || readSource { supported += 1 }
            advance(recorded: true)
        } catch { errorMessage = error.localizedDescription }
    }

    private func advance(recorded: Bool) {
        if recorded { reviewed += 1 } else { skipped += 1 }
        index += 1
        resetAttempt()
        if index >= cardIDs.count { isFinished = true }
    }

    private func resetAttempt() {
        revealed = false
        hintCount = 0
        usedHint = false
        readSource = false
        showSourcePane = false
        presentation = nil
        errorMessage = nil
        eventID = UUID()
    }

}

private struct LearningReviewShortcut: ViewModifier {
    var key: KeyEquivalent
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.keyboardShortcut(key, modifiers: []) } else { content }
    }
}
