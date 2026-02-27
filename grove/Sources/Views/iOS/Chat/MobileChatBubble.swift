import SwiftUI

/// Individual chat message bubble with role-based styling.
/// User messages right-aligned (dark bg), assistant left-aligned (light bg).
struct MobileChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xs) {
                Text(message.content)
                    .font(.groveBody)
                    .foregroundStyle(message.role == .user ? Color.textInverse : Color.textPrimary)
                    .textSelection(.enabled)

                Text(message.createdAt, style: .time)
                    .font(.groveMeta)
                    .foregroundStyle(message.role == .user ? Color.textInverse.opacity(0.7) : Color.textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(message.role == .user ? Color.textPrimary : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                if message.role == .assistant {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}
