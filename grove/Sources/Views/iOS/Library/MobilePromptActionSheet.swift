import SwiftUI

struct MobilePromptActionSheet: View {
    private enum PendingAction {
        case openDialectics
        case startWriting
    }

    let contextTitle: String
    let suggestion: PromptBubble
    let onOpenDialectics: () -> Void
    let onStartWriting: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: PendingAction?
    #if os(iOS)
    @State private var presentationDetent: PresentationDetent = .fraction(0.62)
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    promptCard

                    VStack(spacing: Spacing.sm) {
                        actionCard(
                            title: "Open Dialectics",
                            subtitle: "Start a conversation grounded in this prompt and its context.",
                            systemImage: "bubble.left.and.bubble.right",
                            isPrimary: true,
                            action: {
                                pendingAction = .openDialectics
                            }
                        )

                        actionCard(
                            title: "Start Writing",
                            subtitle: "Open a writing draft seeded by this prompt.",
                            systemImage: "square.and.pencil",
                            isPrimary: false,
                            action: {
                                pendingAction = .startWriting
                            }
                        )
                    }

                    Text("Dialectics opens a discussion. Writing only saves once you add a title or body.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.vertical, Spacing.lg)
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
        .onDisappear {
            runPendingActionIfNeeded()
        }
        #if os(iOS)
        .presentationDetents([.fraction(0.62), .large], selection: $presentationDetent)
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

                Text(contextTitle)
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

    private func runPendingActionIfNeeded() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        Task { @MainActor in
            switch pendingAction {
            case .openDialectics:
                onOpenDialectics()
            case .startWriting:
                onStartWriting()
            }
        }
    }
}
