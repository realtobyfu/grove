import SwiftUI

/// Dismissable toast banner that appears after capture when the auto-tagger
/// suggests a board. Shows the suggestion headline, confidence, and action buttons.
/// Auto-dismisses after 5 seconds (configurable via AppConstants).
struct MobileBoardSuggestionBanner: View {
    let decision: BoardSuggestionDecision
    let onAccept: () -> Void
    let onChoose: () -> Void
    let onDismiss: () -> Void

    private var headline: String {
        switch decision.mode {
        case .existing:
            return "Best fit: \"\(decision.suggestedName)\""
        case .create:
            return "Create board \"\(decision.suggestedName)\"?"
        }
    }

    private var primaryLabel: String {
        switch decision.mode {
        case .existing: return "Add"
        case .create: return "Create"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Top row: icon + headline + dismiss
            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.stack")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Text(headline)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss board suggestion")
            }

            // Reason + confidence
            if !decision.reason.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Text(decision.reason)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(BoardSuggestionEngine.confidenceLabel(for: decision.confidence))
                        .font(.groveBadge)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Action buttons
            HStack(spacing: Spacing.md) {
                Button {
                    onAccept()
                } label: {
                    Text(primaryLabel)
                        .font(.groveBodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Button {
                    onChoose()
                } label: {
                    Text("Choose…")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LayoutDimensions.cardCornerRadius)
                .stroke(Color.borderPrimary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .padding(.horizontal, Spacing.lg)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
