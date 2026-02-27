#if os(macOS)
import AppKit
#endif
import SwiftUI

// MARK: - Growth Stage Indicator

struct GrowthStageIndicator: View {
    let stage: GrowthStage
    var showLabel: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var stageColor: Color {
        Color(hex: colorScheme == .dark ? stage.darkColorHex : stage.colorHex)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: stage.systemImage)
                .font(.system(size: stage.iconSize))
                .foregroundStyle(stageColor)

            if showLabel {
                Text(stage.displayName)
                    .font(.groveBadge)
                    .foregroundStyle(stageColor)
            }
        }
    }
}

struct ItemCardView: View {
    let item: Item
    var showTags: Bool = true
    /// Called when the user chooses "Read in App" from the thumbnail context menu or the badge button.
    var onReadInApp: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        if item.type == .note {
            noteCardBody
        } else {
            sourceCardBody
        }
    }

    // MARK: - Note Card

    private var noteCardBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Type icon + title
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: item.type.iconName)
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
                Text(item.title)
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
            }

            // Content preview
            if let preview = noteContentPreview {
                Text(preview)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }

            // Tags row
            if showTags && !item.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tags.prefix(3)) { tag in
                        TagChip(tag: tag, mode: .display)
                    }
                    if item.tags.count > 3 {
                        Text("+\(item.tags.count - 3)")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Minimal badge row
            HStack(spacing: Spacing.md) {
                GrowthStageIndicator(stage: item.growthStage)
                    .help("\(item.growthStage.displayName) — \(item.depthScore) pts")

                let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
                if connectionCount > 0 {
                    Label("\(connectionCount)", systemImage: "link")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }

                if item.reflections.count > 0 {
                    Label("\(item.reflections.count)", systemImage: "text.alignleft")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .cardStyle()
    }

    private var noteContentPreview: String? {
        guard let content = item.content, !content.isEmpty else { return nil }
        let stripped = content
            .replacingOccurrences(of: #"^#{1,6}\s"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*+]\s"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        return stripped.count > 120 ? String(stripped.prefix(120)) + "…" : stripped
    }

    // MARK: - Source Card (articles, videos, etc.)

    private var sourceCardBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sourceCover

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.type.iconName)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.groveItemTitle)
                        .lineLimit(2)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.metadata["isAIGenerated"] == "true" {
                        Label(
                            item.metadata["isAIEdited"] == "true" ? "Edited" : "AI Draft",
                            systemImage: item.metadata["isAIEdited"] == "true" ? "pencil" : "sparkles"
                        )
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            if let summary = item.metadata["summary"], !summary.isEmpty {
                Text(summary)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            if showTags && !item.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tags.prefix(2)) { tag in
                        TagChip(tag: tag, mode: .capsule)
                    }
                    if item.tags.count > 2 {
                        Text("+\(item.tags.count - 2)")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.md) {
                GrowthStageIndicator(stage: item.growthStage)
                    .help("\(item.growthStage.displayName) — \(item.depthScore) pts")

                let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
                if connectionCount > 0 {
                    Label("\(connectionCount)", systemImage: "link")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }

                if item.reflections.count > 0 {
                    Label("\(item.reflections.count)", systemImage: "text.alignleft")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                if item.metadata["videoLocalFile"] == "true" {
                    Text("Local")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textTertiary)
                } else if let urlString = item.sourceURL, let url = URL(string: urlString) {
                    Button {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        openURL(url)
                        #endif
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                            Text(domainFrom(urlString))
                                .font(.groveBadge)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        .cardStyle(cornerRadius: 12)
    }

    @ViewBuilder
    private var sourceCover: some View {
        if let thumbnailData = item.thumbnail {
            CoverImageView(
                imageData: thumbnailData,
                height: 132,
                showPlayOverlay: item.type == .video,
                cornerRadius: 8
            )
            .onTapGesture {
                onReadInApp?()
            }
        }
    }

}
