import SwiftUI
import SwiftData

/// Individual chat message bubble with role-based styling.
/// User messages right-aligned (dark bg), assistant left-aligned (light bg).
/// Detects [[wiki-links]] in content and renders them as underlined text.
/// Long-press on assistant messages shows action sheet (Save as Reflection, Note, Copy).
struct MobileChatBubble: View {
    let message: ChatMessage
    var onSaveAsReflection: (() -> Void)?
    var onSaveAsNote: (() -> Void)?

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xs) {
                wikiLinkContent
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
            .contextMenu {
                if message.role == .assistant {
                    if let onSaveAsReflection {
                        Button {
                            onSaveAsReflection()
                        } label: {
                            Label("Save as Reflection", systemImage: "text.bubble")
                        }
                    }
                    if let onSaveAsNote {
                        Button {
                            onSaveAsNote()
                        } label: {
                            Label("Save as Note", systemImage: "note.text")
                        }
                    }
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = message.content
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Wiki-link rendering

    /// Renders content with [[wiki-links]] as underlined text.
    @ViewBuilder
    private var wikiLinkContent: some View {
        let segments = parseWikiLinks(message.content)
        if segments.contains(where: { $0.isLink }) {
            segments.reduce(Text("")) { result, segment in
                if segment.isLink {
                    result + Text(segment.text).underline()
                } else {
                    result + Text(segment.text)
                }
            }
        } else {
            Text(message.content)
        }
    }

    private struct TextSegment {
        let text: String
        let isLink: Bool
    }

    private func parseWikiLinks(_ content: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = content[content.startIndex...]

        while let openRange = remaining.range(of: "[[") {
            if remaining.startIndex < openRange.lowerBound {
                segments.append(TextSegment(text: String(remaining[remaining.startIndex..<openRange.lowerBound]), isLink: false))
            }

            let afterOpen = openRange.upperBound
            if let closeRange = remaining[afterOpen...].range(of: "]]") {
                let linkTitle = String(remaining[afterOpen..<closeRange.lowerBound])
                segments.append(TextSegment(text: linkTitle, isLink: true))
                remaining = remaining[closeRange.upperBound...]
            } else {
                segments.append(TextSegment(text: String(remaining[openRange.lowerBound...]), isLink: false))
                return segments
            }
        }

        if !remaining.isEmpty {
            segments.append(TextSegment(text: String(remaining), isLink: false))
        }

        return segments
    }
}
