import SwiftUI
import SwiftData

struct InboxCard: View {
    let item: Item
    let isSelected: Bool
    /// Boards offered as one-click "keep + file" chips, recommended first.
    var suggestedBoards: [Board] = []
    let onKeep: () -> Void
    let onDrop: () -> Void
    var onQueue: ((ReadLaterPreset) -> Void)?
    var onConfirmTag: ((Tag) -> Void)?
    var onDismissTag: ((Tag) -> Void)?
    /// Keep the item and file it into this board in a single gesture.
    var onFileToBoard: ((Board) -> Void)?
    /// Open the full board picker for this item.
    var onMoreBoards: (() -> Void)?

    private var isFetchingMetadata: Bool {
        item.isFetchingMetadata
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Cover image
            if let thumbnailData = item.thumbnail {
                CoverImageView(
                    imageData: thumbnailData,
                    height: 140,
                    showPlayOverlay: item.type == .video,
                    cornerRadius: Radius.control
                )
            }

            // Header row: type icon + title
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if isFetchingMetadata {
                        // URL title not yet resolved — show raw URL in mono
                        Text(item.title)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                        HStack(spacing: Spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching title…")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } else {
                        Text(item.title)
                            .font(.groveItemTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(3)
                    }

                    // Source domain and capture date
                    HStack(spacing: Spacing.sm) {
                        if let url = item.sourceURL, !url.isEmpty {
                            Label(domainFrom(url), systemImage: "link")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        Text(item.createdAt.formatted(.relative(presentation: .named)))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()
            }

            // One-line summary if available
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            } else if let preview = item.previewText {
                // Fall back to content preview
                Text(preview)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }

            // Auto-tags with confirm/dismiss actions
            if !item.tags.isEmpty {
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(item.tags.prefix(5)) { tag in
                        TagChip(tag: tag, mode: .autoTag(
                            onConfirm: { onConfirmTag?(tag) },
                            onDismiss: { onDismissTag?(tag) }
                        ))
                    }
                    if item.tags.count > 5 {
                        Text("+\(item.tags.count - 5)")
                            .font(.groveTag)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            // One-gesture filing: keep + assign, no modal.
            if onFileToBoard != nil || onMoreBoards != nil {
                boardChipsRow
            }

            Divider()

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button {
                    onKeep()
                } label: {
                    Label("Keep unfiled", systemImage: "checkmark.circle")
                }
                .buttonStyle(.grove(.primary, size: .compact))
                .help("Keep without filing to a board. Shortcut: 1")

                Menu {
                    ForEach(ReadLaterPreset.allCases) { preset in
                        Button {
                            onQueue?(preset)
                        } label: {
                            Text(preset.label)
                        }
                    }
                } label: {
                    Label("Later", systemImage: "clock")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.grove(.secondary, size: .compact))
                .disabled(onQueue == nil)
                .help("Shortcut: 3 queues until tomorrow morning")

                Button {
                    onDrop()
                } label: {
                    Label("Drop", systemImage: "xmark.circle")
                }
                .buttonStyle(.grove(.secondary, size: .compact))
                .help("Shortcut: 2")
            }
        }
        .padding(Spacing.lg)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .selectedItemStyle(isSelected)
    }

    // MARK: - Board Chips

    /// Recommended board first, then up to two alternates, then "More…".
    /// Tapping a chip keeps and files the item in one action.
    private var boardChipsRow: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text("File to")
                .sectionHeaderStyle()
                .fixedSize()

            chipFlow
        }
    }

    private var chipFlow: some View {
        FlowLayout(spacing: Spacing.xsm) {
            ForEach(Array(suggestedBoards.prefix(3).enumerated()), id: \.element.id) { index, board in
                BoardFilingChip(
                    title: board.title,
                    isRecommended: index == 0,
                    action: { onFileToBoard?(board) }
                )
                .help("Keep and file to \(board.title)")
            }

            if let onMoreBoards {
                BoardFilingChip(
                    title: suggestedBoards.isEmpty ? "Choose board\u{2026}" : "More\u{2026}",
                    isRecommended: false,
                    action: onMoreBoards
                )
                .help("Choose a board")
            }

            if let newBoardName = suggestedNewBoardName {
                Text("suggests new board \u{201C}\(newBoardName)\u{201D}")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Set only when the engine proposed a board that doesn't exist yet —
    /// there's nothing to file into, so the name is offered as a hint.
    private var suggestedNewBoardName: String? {
        guard suggestedBoards.isEmpty,
              let decision = BoardSuggestionMetadata.decision(from: item),
              decision.mode == .create,
              !decision.suggestedName.isEmpty else { return nil }
        return decision.suggestedName
    }
}

// MARK: - Filing Chip

/// Quiet monochrome chip. The recommended board reads in full ink with a
/// solid hairline; alternates sit back in secondary ink.
private struct BoardFilingChip: View {
    let title: String
    let isRecommended: Bool
    let action: () -> Void

    @State private var isHovering = false

    private static let verticalPadding: CGFloat = 3

    private var ink: Color {
        if isHovering { return Color.textPrimary }
        return isRecommended ? Color.textPrimary : Color.textSecondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.groveBodySmall)
                .foregroundStyle(ink)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Self.verticalPadding)
                #if os(iOS)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
                #endif
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.tag)
                        .stroke(
                            isRecommended || isHovering ? Color.borderPrimary : Color.borderTag,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
