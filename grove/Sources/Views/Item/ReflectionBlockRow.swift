import SwiftUI
import SwiftData

struct ReflectionBlockRow: View {
    let block: ReflectionBlock
    var onEdit: (ReflectionBlock) -> Void
    var onDelete: (ReflectionBlock) -> Void
    var onNavigateToItemByTitle: (String) -> Void
    /// Jump to the highlighted passage in the source (nil when the item has
    /// no web-readable source to scroll).
    var onHighlightTap: ((String) -> Void)? = nil
    var onRemember: ((ReflectionBlock) -> Void)? = nil
    var modelContext: ModelContext

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: type label + actions
            HStack(spacing: 6) {
                Text(block.blockType.displayName)
                    .font(.groveBadge)
                    .tracking(0.5)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text(block.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)

                if let onRemember {
                    Button {
                        onRemember(block)
                    } label: {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Make a flashcard from this reflection")
                    .help("Make a flashcard")
                    #if os(iOS)
                    .frame(minWidth: 44, minHeight: 44)
                    #endif
                }

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
                HighlightQuoteChip(
                    quote: highlight,
                    onJump: onHighlightTap.map { tap in { tap(highlight) } }
                )
                .padding(.leading, 4)
            }

            // Content
            if block.content.isEmpty {
                Text("Click to add your reflection...")
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownTextView(markdown: block.content, scale: .prose, onWikiLinkTap: onNavigateToItemByTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The whole row is the edit target — buttons, menus, and links inside
        // still win their own taps, but padding and header whitespace no
        // longer swallow the click.
        .contentShape(Rectangle())
        .onTapGesture { onEdit(block) }
        // Hover marks the row the way the rest of the app does: a left rule
        // in ink, not a filled card floating off the page.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.textPrimary)
                .frame(width: 2)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
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
