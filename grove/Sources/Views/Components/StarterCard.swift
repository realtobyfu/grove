import SwiftUI

/// A conversation starter with both ways forward on the card itself. Shared by
/// Today and board pages on every platform; each surface supplies the actions
/// because each scopes seed items and metering its own way.
struct StarterCard: View {
    let bubble: PromptBubble
    let onOpenChat: () -> Void
    let onStartWriting: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            Text(bubble.prompt)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentSelection)
                .frame(width: 2)
        }
        .cardStyle(cornerRadius: 8)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(bubble.displayLabel)
                .font(.groveBadge)
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.groveMeta)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textMuted)
                        .frame(width: StarterCardMetrics.minTarget, height: StarterCardMetrics.minTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // The target overhangs the header so a 44pt hit area doesn't
                // push the prompt down.
                .padding(.vertical, -Spacing.sm)
                .padding(.trailing, -Spacing.sm)
                .accessibilityLabel("Dismiss suggestion")
            }
        }
    }

    /// Side by side when both fit, stacked at large text sizes so neither truncates.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                openChatAction
                startWritingAction
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                openChatAction
                startWritingAction
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openChatAction: some View {
        StarterCardAction(
            title: "Open Chat",
            systemImage: "bubble.left.and.bubble.right",
            action: onOpenChat
        )
    }

    private var startWritingAction: some View {
        StarterCardAction(
            title: "Start Writing",
            systemImage: "square.and.pencil",
            action: onStartWriting
        )
    }
}

private enum StarterCardMetrics {
    #if os(iOS)
    static let minTarget = LayoutDimensions.minTouchTarget
    #else
    static let minTarget: CGFloat = 28
    #endif
}

private struct StarterCardAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.groveBodySmall)
                .foregroundStyle(isHovered ? Color.textPrimary : Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: StarterCardMetrics.minTarget)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isHovered ? Color.borderInput : Color.borderPrimary, lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
