import SwiftUI
import SwiftData

/// Non-blocking popover showing connection suggestions after item/annotation save.
/// Shows top 3 suggestions with accept/dismiss actions.
struct ConnectionSuggestionPopover: View {
    let sourceItem: Item
    let suggestions: [ConnectionSuggestion]
    let onAccept: (ConnectionSuggestion) -> Void
    let onDismiss: (ConnectionSuggestion) -> Void
    let onDismissAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "link.badge.plus")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                Text("SUGGESTED CONNECTIONS")
                    .font(.groveSectionHeader)
                    .tracking(1.2)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Button {
                    onDismissAll()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }

            ForEach(suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    private func suggestionRow(_ suggestion: ConnectionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.targetItem.type.iconName)
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 12)
                Text(suggestion.targetItem.title)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 4) {
                Text(suggestion.suggestedType.displayLabel)
                    .font(.groveBadge)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentBadge)
                    .clipShape(Capsule())

                Text(suggestion.reason)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                Spacer()

                Button {
                    onAccept(suggestion)
                } label: {
                    Text("Connect")
                        .font(.groveBodySmall)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(Color.textPrimary)

                Button {
                    onDismiss(suggestion)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(6)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
    }
}
