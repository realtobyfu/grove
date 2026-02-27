import SwiftUI
import SwiftData

/// Renders a single chat message bubble with appropriate styling for each role.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let conversation: Conversation
    let dialecticsService: DialecticsService
    var onWikiLinkTapped: ((String) -> Void)?
    var onConnectionRequest: (ChatMessage) -> Void
    var onReflectionRequest: (ChatMessage, Conversation) -> Void
    var onNoteRequest: (ChatMessage) -> Void

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .system:
            systemBubble
        case .assistant:
            assistantBubble
        case .tool:
            EmptyView()
        }
    }

    // MARK: - System Bubble

    private var systemBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("DISCUSSION PROMPT")
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                Text(message.content)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )

            Spacer(minLength: 40)
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(.groveBody)
                .foregroundStyle(Color.textInverse)
                .padding(Spacing.md)
                .background(Color.accentSelection)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                MarkdownTextView(markdown: message.content) { title in
                    onWikiLinkTapped?(title)
                }
                .textSelection(.enabled)

                assistantActions
            }
            .padding(Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentSelection)
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Assistant Actions

    private var assistantActions: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                #else
                UIPasteboard.general.string = message.content
                #endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.groveBadge)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textMuted)

            Button {
                onNoteRequest(message)
            } label: {
                Label("Save as note", systemImage: "note.text.badge.plus")
                    .font(.groveBadge)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textMuted)

            if !message.referencedItemIDs.isEmpty {
                Button {
                    onReflectionRequest(message, conversation)
                } label: {
                    Label("Save as Reflection", systemImage: "text.badge.plus")
                        .font(.groveBadge)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
            }

            if message.referencedItemIDs.count >= 2 {
                Button {
                    onConnectionRequest(message)
                } label: {
                    Label("Create Connection", systemImage: "link.badge.plus")
                        .font(.groveBadge)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Thinking Indicator

struct ChatThinkingIndicator: View {
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text("Thinking")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                ProgressView()
                    .controlSize(.mini)
            }
            .padding(Spacing.sm)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
    }
}

// MARK: - Error Bubble

struct ChatErrorBubble: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.groveBody)
                .foregroundStyle(Color.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unable to respond")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                Text(message)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }
}
