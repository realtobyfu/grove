import SwiftUI
import SwiftData

/// The input area at the bottom of a dialectics chat conversation.
struct ChatInputArea: View {
    @Binding var inputText: String
    let conversation: Conversation
    let isGenerating: Bool
    let seeds: [Item]
    var onSend: () -> Void
    var onNavigateToItem: ((Item) -> Void)?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if !seeds.isEmpty {
                seedItemPills
            }

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("Ask, challenge, or reflect...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.groveBody)
                    .lineLimit(1...5)
                    .padding(Spacing.sm)
                    .background(Color.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.borderInput, lineWidth: 1)
                    )
                    .onSubmit {
                        onSend()
                    }

                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.textMuted : Color.textPrimary
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .accessibilityLabel("Send message")
                .accessibilityHint("Submits your current prompt to Dialectics.")
            }
        }
        .padding(Spacing.md)
    }

    // MARK: - Seed Item Pills

    private var seedItemPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                Text("Context:")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textMuted)
                ForEach(seeds, id: \.id) { item in
                    Button {
                        onNavigateToItem?(item)
                    } label: {
                        Text(item.title)
                            .font(.groveBadge)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentBadge)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
