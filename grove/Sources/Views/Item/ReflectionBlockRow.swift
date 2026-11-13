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

    /// Hover reveals delete on the Mac; a touch screen has no hover to reveal it.
    private var deleteOpacity: Double {
        #if os(iOS)
        1
        #else
        isHovered ? 1 : 0
        #endif
    }

    /// The 44pt targets sit edge to edge on iOS, where the header is tightest.
    private var headerActionSpacing: CGFloat {
        #if os(iOS)
        0
        #else
        6
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: type label + actions
            HStack(spacing: headerActionSpacing) {
                Text(block.blockType.displayName)
                    .font(.groveBadge)
                    .tracking(0.5)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text(block.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)

                if let onRemember {
                    Button {
                        onRemember(block)
                    } label: {
                        headerActionIcon("rectangle.on.rectangle", color: Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Make a flashcard from this reflection")
                    .help("Make a flashcard")
                }

                // Type menu
                Menu {
                    typeOptions
                } label: {
                    headerActionIcon(block.blockType.systemImage, color: Color.textSecondary)
                }
                .menuStyle(.borderlessButton)
                #if os(macOS)
                .frame(width: 20)
                #endif
                .accessibilityLabel("Change type")
                .help("Change type")

                // Delete -- hover on the Mac, always visible on touch
                Button {
                    onDelete(block)
                } label: {
                    headerActionIcon("trash", color: Color.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete reflection")
                .help("Delete")
                .opacity(deleteOpacity)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }

            // Highlight (linked source text)
            if let highlight = block.highlight, !highlight.isEmpty {
                HighlightQuoteChip(
                    quote: highlight,
                    onJump: onHighlightTap.map { tap in { tap(highlight) } }
                )
                .padding(.leading, Spacing.xs)
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
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        // The whole row is the edit target — buttons, menus, and links inside
        // still win their own taps, but padding and header whitespace no
        // longer swallow the click.
        .contentShape(Rectangle())
        .onTapGesture { onEdit(block) }
        .contextMenu {
            Menu("Change Type") {
                typeOptions
            }
            Button(role: .destructive) {
                onDelete(block)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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

    private var typeOptions: some View {
        ForEach(ReflectionBlockType.allCases, id: \.self) { type in
            Button {
                block.blockType = type
                try? modelContext.save()
            } label: {
                Label(type.displayName, systemImage: type.systemImage)
            }
        }
    }

    /// Header glyph. On iOS the 44pt frame and hit shape live inside the
    /// control's label: a plain button only hit-tests what its label draws.
    private func headerActionIcon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.groveMeta)
            .foregroundStyle(color)
            #if os(iOS)
            .frame(width: LayoutDimensions.minTouchTarget, height: LayoutDimensions.minTouchTarget)
            .contentShape(Rectangle())
            #endif
    }
}
