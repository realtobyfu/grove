import SwiftUI
import SwiftData

struct ReflectionBlockRow: View {
    let block: ReflectionBlock
    let isVideoItem: Bool
    @Binding var videoSeekTarget: Double?
    var onEdit: (ReflectionBlock) -> Void
    var onDelete: (ReflectionBlock) -> Void
    var onNavigateToItemByTitle: (String) -> Void
    var modelContext: ModelContext

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: type label + video timestamp + actions
            HStack(spacing: 6) {
                Text(block.blockType.displayName)
                    .font(.groveBadge)
                    .tracking(0.5)
                    .foregroundStyle(Color.textTertiary)

                // Video timestamp seek button
                if isVideoItem, let ts = block.videoTimestamp {
                    Button {
                        videoSeekTarget = Double(ts)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption2)
                            Text(Double(ts).formattedTimestamp)
                                .font(.groveMeta)
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to \(Double(ts).formattedTimestamp) in video")
                }

                Spacer()

                Text(block.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)

                // Type menu
                Menu {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Button {
                            block.blockType = type
                            try? modelContext.save()
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: block.blockType.systemImage)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Change type")

                // Delete -- hover only
                Button {
                    onDelete(block)
                } label: {
                    Image(systemName: "trash")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Delete")
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }

            // Highlight (linked source text)
            if let highlight = block.highlight, !highlight.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.borderPrimary)
                        .frame(width: 2)
                    Text(highlight)
                        .font(.groveGhostText)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                }
                .padding(.leading, 4)
            }

            // Content -- click to edit
            if block.content.isEmpty {
                Text("Click to add your reflection...")
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(block) }
            } else {
                MarkdownTextView(markdown: block.content, onWikiLinkTap: onNavigateToItemByTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(block) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.bgCardHover : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
            #if os(macOS)
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
            #endif
        }
    }
}
