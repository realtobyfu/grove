import SwiftUI

struct MobilePromptActionSheet: View {
    let boardTitle: String
    let suggestion: PromptBubble
    let onOpenDialectics: () -> Void
    let onStartWriting: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    promptCard

                    VStack(spacing: Spacing.md) {
                        actionCard(
                            title: "Open Dialectics",
                            subtitle: "Start a conversation grounded in this board's context.",
                            systemImage: "bubble.left.and.bubble.right",
                            isPrimary: true,
                            action: {
                                onOpenDialectics()
                            }
                        )

                        actionCard(
                            title: "Start Writing",
                            subtitle: "Turn this prompt into a new note and keep building the board.",
                            systemImage: "square.and.pencil",
                            isPrimary: false,
                            action: {
                                onStartWriting()
                            }
                        )
                    }

                    Text("Dialectics opens a discussion. Writing creates a note seeded with this prompt.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.vertical, LayoutDimensions.sectionSpacing)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Prompt Actions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PROMPT ACTIONS")
                .sectionHeaderStyle()

            Text("Choose how you want to use this discussion seed.")
                .font(.groveBodySecondary)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text(suggestion.label.uppercased())
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)

                Text(boardTitle)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Text(suggestion.prompt)
                .font(.groveBodyLarge)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPrimary ? Color.textInverse : Color.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isPrimary ? Color.textPrimary.opacity(0.18) : Color.bgInspector)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.groveBodyMedium)
                            .foregroundStyle(isPrimary ? Color.textInverse : Color.textPrimary)

                        Text(subtitle)
                            .font(.groveBodySmall)
                            .foregroundStyle(isPrimary ? Color.textInverse.opacity(0.82) : Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPrimary ? Color.textInverse.opacity(0.82) : Color.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(isPrimary ? Color.textPrimary : Color.bgCard)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isPrimary ? Color.clear : Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
