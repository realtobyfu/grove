import SwiftUI
import SQLiteData

/// The quote is a captured source snapshot, never the generated answer.
struct LearningSourcePassageView: View {
    let card: Flashcard
    var onRetry: (() -> Void)? = nil
    var onReadOriginal: (() -> Void)? = nil
    var onOpenSource: ((Flashcard) -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Fetch(Library.Request()) private var library = Library()
    @State private var showOriginal = false

    private var sourceItem: ItemGraph? { library.item(card.sourceItemID) }

    private var sourceLocation: String? {
        guard let locator = card.sourceLocator, !locator.isEmpty else { return nil }
        if locator.hasPrefix("video:"), let seconds = Double(locator.dropFirst(6)) {
            return seconds.formattedTimestamp
        }
        return locator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(card.sourceTitle.isEmpty ? "Saved source" : card.sourceTitle)
                    .font(.groveItemTitle)
                if let locator = sourceLocation {
                    Text(locator).font(.groveMeta).foregroundStyle(Color.textTertiary)
                }
                if let quote = card.sourceQuote, !quote.isEmpty {
                    Text(quote)
                        .font(.groveSerif)
                        .textSelection(.enabled)
                        .padding(.leading, Spacing.md)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.textPrimary).frame(width: 2)
                        }
                    Text("Saved passage · original may have changed")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Text("No saved passage. Open the source below if available.")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                }
                if sourceItem == nil, card.sourceItemID != nil {
                    Text("Source removed from library")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
                if let onRetry {
                    Button("Back to question", action: onRetry)
                        .buttonStyle(LearningPrimaryButtonStyle())
                }
                if sourceItem != nil {
                    Button {
                        onReadOriginal?()
                        if let onOpenSource { onOpenSource(card) } else { showOriginal = true }
                    } label: {
                        Label("Open source", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LearningSecondaryButtonStyle())
                } else if let raw = card.sourceURL, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Button {
                        onReadOriginal?()
                        openURL(url)
                    } label: {
                        Label("Open website", systemImage: "arrow.up.right")
                    }
                    .font(.groveBodySmall)
                    .frame(minHeight: 44)

                }
            }
            .padding(Spacing.lg)
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showOriginal) {
            LearningOriginalSourceView(card: card, onReturnToQuestion: onRetry)
        }
    }
}

private struct LearningOriginalSourceView: View {
    let card: Flashcard
    var onReturnToQuestion: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Fetch(Library.Request()) private var library = Library()
    @State private var webViewActive = false

    var body: some View {
        NavigationStack {
            Group {
                if let item = library.item(card.sourceItemID) {
                    #if os(iOS)
                    MobileItemReaderView(item: item, preferFullScreenReaderExperience: true)
                    #else
                    ItemReaderView(item: item, isWebViewActive: $webViewActive)
                    #endif
                } else {
                    ContentUnavailableView("Original unavailable", systemImage: "doc.text", description: Text("Return to your flashcard to continue."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to question") {
                        onReturnToQuestion?()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 650)
        #endif
    }
}
