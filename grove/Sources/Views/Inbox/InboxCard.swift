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
                InboxFilingRow(
                    item: item,
                    suggestedBoards: suggestedBoards,
                    onFileToBoard: onFileToBoard,
                    onMoreBoards: onMoreBoards
                )
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
}

// MARK: - Focus Card

/// The inbox item being triaged on Today, set large: everything `InboxCard`
/// shows, with the key that does each thing marked on its button. The keys
/// themselves are handled by `InboxTriageView`, which owns the focus.
struct InboxFocusCard: View {
    let item: Item
    /// Boards offered as one-click "keep + file" chips, recommended first.
    var suggestedBoards: [Board] = []
    /// The card is wide enough for the cover to sit beside the text.
    /// Otherwise the cover runs across the top.
    var coverBeside = true
    let onKeep: () -> Void
    let onDrop: () -> Void
    var onQueue: ((ReadLaterPreset) -> Void)?
    /// Open the item in the reader.
    var onOpen: (() -> Void)?
    var onConfirmTag: ((Tag) -> Void)?
    var onDismissTag: ((Tag) -> Void)?
    /// Keep the item and file it into this board in a single gesture.
    var onFileToBoard: ((Board) -> Void)?
    /// Open the full board picker for this item.
    var onMoreBoards: (() -> Void)?

    /// How wide the cover runs when it sits beside the text.
    private static let sideCoverWidth: CGFloat = 150

    var body: some View {
        if ThemeStore.shared.theme.usesRules {
            ruledEntry
        } else {
            slip
        }
    }

    // MARK: Slip (Grove)

    /// The focused arrival as an index slip, in three bands: where it came
    /// from, what it is, what to do with it. A hairline outlines it and an
    /// ink line in the margin marks it as the one in hand. The cover runs
    /// flush to the slip's edge at the body's height.
    private var slip: some View {
        VStack(alignment: .leading, spacing: 0) {
            metaLine
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)

            SlipRule()

            if !coverBeside, let thumbnailData = item.thumbnail {
                CoverImageView(
                    imageData: thumbnailData,
                    height: TodayLayout.coverBannerHeight,
                    showPlayOverlay: item.type == .video,
                    cornerRadius: 0
                )
                SlipRule()
            }

            text
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the cover, which is laid over this band so that it
                // takes the band's height whatever the text comes to.
                .padding(.trailing, hasSideCover ? Self.sideCoverWidth : 0)
                .overlay(alignment: .trailing) { sideCover }

            SlipRule()

            actions
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgPrimary)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Color.borderInput, lineWidth: 1)
        )
        .overlay(alignment: .leading) { emphasisMark(inset: Radius.card) }
    }

    /// The mark that says "this one": a straight ink line standing in the
    /// margin beside the slip. It is drawn outside the slip, clear of its
    /// rounded corners, so it stays a line rather than bending into a
    /// coloured border.
    private func emphasisMark(inset: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentSelection)
            .frame(width: 2)
            .padding(.vertical, inset)
            .offset(x: -Spacing.md)
            .accessibilityHidden(true)
    }

    private var hasSideCover: Bool {
        coverBeside && item.thumbnail != nil
    }

    @ViewBuilder
    private var sideCover: some View {
        if coverBeside, let thumbnailData = item.thumbnail {
            GeometryReader { geometry in
                CoverImageView(
                    imageData: thumbnailData,
                    height: geometry.size.height,
                    showPlayOverlay: item.type == .video,
                    cornerRadius: 0
                )
            }
            .frame(width: Self.sideCoverWidth)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(width: 1)
            }
        }
    }

    // MARK: Ruled entry (Commonplace)

    /// The same content with no box: set on the page, closed by a rule.
    private var ruledEntry: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if !coverBeside {
                cover(width: nil, height: TodayLayout.coverBannerHeight)
            }

            HStack(alignment: .top, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    metaLine
                    text
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if coverBeside {
                    cover(width: TodayLayout.coverSize.width, height: TodayLayout.coverSize.height)
                }
            }

            actions
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { SlipRule() }
        .overlay(alignment: .leading) { emphasisMark(inset: Spacing.lg) }
    }

    // MARK: Cover

    @ViewBuilder
    private func cover(width: CGFloat?, height: CGFloat) -> some View {
        if let thumbnailData = item.thumbnail {
            CoverImageView(
                imageData: thumbnailData,
                height: height,
                showPlayOverlay: item.type == .video,
                cornerRadius: Radius.control
            )
            .frame(width: width)
        }
    }

    // MARK: Text

    /// Title, summary, auto-tags and the filing chips.
    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock

            if let summaryText {
                Text(summaryText)
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(4)
                    .padding(.top, Spacing.xsm)
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
                .padding(.top, Spacing.md)
            }

            // One-gesture filing: keep + assign, no modal.
            if onFileToBoard != nil || onMoreBoards != nil {
                InboxFilingRow(
                    item: item,
                    suggestedBoards: suggestedBoards,
                    onFileToBoard: onFileToBoard,
                    onMoreBoards: onMoreBoards
                )
                .padding(.top, Spacing.md)
            }
        }
    }

    /// Type, source and age on one mono line.
    private var metaLine: some View {
        HStack(spacing: Spacing.xsm) {
            ItemTypeMark(type: item.type, label: item.type.displayName)

            Text(metaText)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
    }

    private var metaText: String {
        var parts: [String] = []
        if let url = item.sourceURL, !url.isEmpty {
            parts.append(domainFrom(url))
        }
        parts.append(item.createdAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var titleBlock: some View {
        if item.isFetchingMetadata {
            // URL title not yet resolved — show raw URL in mono
            Text(item.title)
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Fetching title\u{2026}")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.top, Spacing.xs)
        } else {
            Text(item.title)
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
        }
    }

    /// The one-line summary, or the content preview when there is none.
    private var summaryText: String? {
        if let summary = item.summary, !summary.isEmpty { return summary }
        return item.previewText
    }

    // MARK: Actions

    /// Keep, Later, Drop and Read now, labelled as the inbox card always
    /// labelled them. The keys (1, 2, 3, Return) still work and are named in
    /// each button's tooltip; they are not printed on the buttons. They wrap
    /// onto a second line in a narrow column rather than truncate.
    private var actions: some View {
        FlowLayout(spacing: Spacing.sm) {
            Button(action: onKeep) {
                actionLabel("Keep unfiled", systemImage: "checkmark.circle")
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
                actionLabel("Later", systemImage: "clock")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.grove(.secondary, size: .compact))
            .disabled(onQueue == nil)
            .fixedSize()
            .help("Shortcut: 3 queues until tomorrow morning")

            Button(action: onDrop) {
                actionLabel("Drop", systemImage: "xmark.circle")
            }
            .buttonStyle(.grove(.secondary, size: .compact))
            .help("Shortcut: 2")

            if let onOpen {
                Button(action: onOpen) {
                    Text(item.type == .note ? "Open" : "Read now")
                }
                .buttonStyle(.grove(.secondary, size: .compact))
                .help("Open in the reader. Shortcut: Return")
            }
        }
    }

    /// A button label with its symbol in Grove, the word alone in Commonplace.
    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if ThemeStore.shared.theme.usesGlyphs {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

// MARK: - Slip Rule

/// The hairline between a slip's bands.
private struct SlipRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderPrimary)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Filing Row

/// "File to" and the one-click board chips: the recommended board first,
/// then up to two alternates, then "More…". Tapping a chip keeps and files
/// the item in one action. Shared by `InboxCard` and `InboxFocusCard`.
private struct InboxFilingRow: View {
    let item: Item
    let suggestedBoards: [Board]
    let onFileToBoard: ((Board) -> Void)?
    let onMoreBoards: (() -> Void)?

    var body: some View {
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
