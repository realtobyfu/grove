import SwiftUI
import SwiftData

/// Learning sits alongside the library's other actions, without a promotion card.
struct LearningInvitationView: View {
    var boardID: UUID? = nil
    var onReview: (() -> Void)? = nil
    /// Today shows the row only while cards are due; board pages always show it.
    var showsOnlyWhenDue = false
    /// Spacing that belongs to the row, so a hidden row leaves no gap behind.
    var rowInsets = EdgeInsets()

    private enum Presentation: String, Identifiable {
        case review, focus, library
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var cards: [Flashcard]
    @Query private var reviews: [FlashcardReview]
    @Query(sort: \LearningPreferences.updatedAt, order: .reverse) private var preferences: [LearningPreferences]
    @State private var presentation: Presentation?

    private var readyCount: Int {
        cards.filter { card in
            guard card.deletedAt == nil, !card.isSuspended, card.dueAt <= .now else { return false }
            if let boardID { return card.boardIDs.contains(boardID) }
            let focus = preferences.first?.focusBoardIDs ?? []
            return focus.isEmpty || focus.contains(where: card.boardIDs.contains)
        }.count
    }

    /// An open sheet keeps the row: finishing the last due card must not pull
    /// the review out from under the session.
    private var isRowVisible: Bool {
        !showsOnlyWhenDue || readyCount > 0 || presentation != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if isRowVisible {
                row.padding(rowInsets)
            }
            // A leaf that survives a hidden row, so the task below still runs:
            // it is what brings imported reviews into `dueAt`.
            Color.clear.frame(height: 0)
        }
        .task(id: reviews.map(\.id)) {
            // Imported events, rather than a remote cached due date, determine
            // whether the row offers a review.
            _ = LearningService(modelContext: modelContext).dueCards(boardID: boardID)
        }
        .sheet(item: $presentation) { value in
            NavigationStack {
                switch value {
                case .review: LearningReviewView(boardID: boardID)
                case .focus: LearningFocusView()
                case .library: FlashcardLibraryView(boardID: boardID)
                }
            }
            #if os(macOS)
            .frame(width: value == .review ? 680 : 520, height: value == .review ? 500 : 520)
            #endif
        }
    }

    private var row: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            Text("Flashcards").font(.groveBodySmall)
            if readyCount > 0 {
                Text("\(readyCount) ready")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: Spacing.sm)
            Button(readyCount > 0 ? "Review" : "Open") {
                if readyCount > 0 {
                    if let onReview { onReview() } else { presentation = .review }
                } else { presentation = .library }
            }
            .buttonStyle(.grove(.primary, size: .compact))
            .frame(minHeight: 44)
            .accessibilityLabel(readyCount > 0 ? "Review \(readyCount) flashcards" : "Open flashcards")

            Menu {
                Button("Flashcards") { presentation = .library }
                Button("Focus & session length") { presentation = .focus }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Review options")
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.vertical, Spacing.xs)
        .overlay(alignment: .bottom) { Divider() }
    }
}
