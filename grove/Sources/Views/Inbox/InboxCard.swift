import SwiftUI
import SwiftData

struct InboxCard: View {
    let item: Item
    let isSelected: Bool
    let onKeep: () -> Void
    let onDrop: () -> Void
    var onConfirmTag: ((Tag) -> Void)?
    var onDismissTag: ((Tag) -> Void)?

    private var isFetchingMetadata: Bool {
        item.metadata["fetchingMetadata"] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Cover image
            if let thumbnailData = item.thumbnail {
                CoverImageView(
                    imageData: thumbnailData,
                    height: 140,
                    showPlayOverlay: item.type == .video,
                    cornerRadius: 6
                )
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
                        autoTagChip(tag)
                    }
                    if item.tags.count > 5 {
                        Text("+\(item.tags.count - 5)")
                            .font(.groveTag)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            // Suggested board
            if let suggestedBoard = item.metadata["suggestedBoard"], !suggestedBoard.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                    Text("Suggested board:")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                    Text(suggestedBoard)
                        .font(.groveBadge)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button {
                    onKeep()
                } label: {
                    Label("Keep", systemImage: "checkmark.circle")
                        .font(.groveBodyMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.textPrimary)
                .controlSize(.small)
                .help("Shortcut: 1")

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

    // MARK: - Tag Chip

    @ViewBuilder
    private func autoTagChip(_ tag: Tag) -> some View {
        HStack(spacing: 3) {
            Text(tag.name)
                .font(.groveTag)
                .foregroundStyle(tag.isAutoGenerated ? Color.textSecondary : Color.textPrimary)

            if tag.isAutoGenerated {
                // Confirm button
                Button {
                    onConfirmTag?(tag)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Confirm tag")

                // Dismiss button
                Button {
                    onDismissTag?(tag)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Remove tag")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    style: tag.isAutoGenerated
                        ? StrokeStyle(lineWidth: 1, dash: [3, 2])
                        : StrokeStyle(lineWidth: 1)
                )
                .foregroundStyle(tag.isAutoGenerated ? Color.borderTagDashed : Color.borderTag)
        )
    }

    private func domainFrom(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
