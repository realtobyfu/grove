import SwiftUI

struct InboxCard: View {
    let item: ItemGraph
    let isSelected: Bool
    /// Boards offered as one-click "keep + file" chips, recommended first.
    var suggestedBoards: [BoardGraph] = []
    let onKeep: () -> Void
    let onDrop: () -> Void
    var onQueue: ((ReadLaterPreset) -> Void)?
    var onConfirmTag: ((Tag) -> Void)?
    var onDismissTag: ((Tag) -> Void)?
    /// Keep the item and file it into this board in a single gesture.
    var onFileToBoard: ((BoardGraph) -> Void)?
    /// Open the full board picker for this item.
    var onMoreBoards: (() -> Void)?
    /// Display domain of a site that publishes a feed the user isn't following
    /// yet. Set only when following is actually offerable — the chip renders
    /// whenever this and `onFollowSite` are both present.
    var followableSite: String? = nil
    /// Subscribe to `followableSite`'s feed.
    var onFollowSite: (() -> Void)?

    private var isFetchingMetadata: Bool {
        item.metadata["fetchingMetadata"] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Cover image
            ItemThumbnailReader(itemID: item.id) { thumbnailData in
                if let thumbnailData {
                    CoverImageView(
                        imageData: thumbnailData,
                        height: 140,
                        showPlayOverlay: item.type == .video,
                        cornerRadius: 6
                    )
                }
            }

            // Header row: type icon + title
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    if isFetchingMetadata {
                        // URL title not yet resolved — show raw URL in mono
                        Text(item.title)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                        HStack(spacing: 4) {
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
                    HStack(spacing: 8) {
                        if let url = item.sourceURL, !url.isEmpty {
                            Label(domainFrom(url), systemImage: "link")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        if let followableSite, let onFollowSite {
                            FollowSiteButton(site: followableSite, action: onFollowSite)
                        }

                        Text(item.createdAt.formatted(.relative(presentation: .named)))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()
            }

            // One-line summary if available
            if let summary = item.metadata["summary"], !summary.isEmpty {
                Text(summary)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            } else if let content = item.content, !content.isEmpty {
                // Fall back to content preview
                Text(content)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }

            // Auto-tags with confirm/dismiss actions
            if !item.tags.isEmpty {
                FlowLayout(spacing: 4) {
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
                        .font(.groveBodyMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.textPrimary)
                .controlSize(.small)
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
                        .font(.groveBodyMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(onQueue == nil)
                .help("Shortcut: 3 queues until tomorrow morning")

                Button {
                    onDrop()
                } label: {
                    Label("Drop", systemImage: "xmark.circle")
                        .font(.groveBodyMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Shortcut: 2")
            }
        }
        .padding(Spacing.lg)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        FlowLayout(spacing: 6) {
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

// MARK: - Follow Site Button

/// Quiet inline "+ Follow" that sits in the meta row and reads as meta text:
/// no fill, no border, secondary ink that darkens on hover. Following happens
/// where the user is already looking at the site's work, not in Settings.
private struct FollowSiteButton: View {
    let site: String
    let action: () -> Void

    @State private var isHovering = false

    /// The label is small by design, so iOS pads the hit region out to the
    /// 44pt minimum without changing how the text looks.
    #if os(iOS)
    private static let minTapTarget: CGFloat = 44
    #else
    private static let minTapTarget: CGFloat = 0
    #endif

    var body: some View {
        Button(action: action) {
            Text("+ Follow")
                .font(.groveMeta)
                .foregroundStyle(isHovering ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: Self.minTapTarget, minHeight: Self.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Follow \(site) \u{2014} new posts appear in Following")
        .accessibilityLabel("Follow \(site)")
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
                .padding(.horizontal, 8)
                .padding(.vertical, Self.verticalPadding)
                #if os(iOS)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
                #endif
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
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
