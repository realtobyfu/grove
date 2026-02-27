import SwiftUI

/// Compact list row for items on iOS — title, source domain, growth indicator,
/// optional thumbnail. Minimum 44pt height for touch targets.
struct MobileItemCardView: View {
    let item: Item

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Thumbnail (if available)
            if let thumbnailData = item.thumbnail {
                thumbnailImage(thumbnailData)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Title
                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Spacing.sm) {
                    // Growth stage indicator
                    HStack(spacing: 3) {
                        Image(systemName: item.growthStage.systemImage)
                            .font(.system(size: item.growthStage.iconSize))
                            .foregroundStyle(Color.textTertiary)
                        Text(item.growthStage.displayName)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Source domain
                    if let sourceURL = item.sourceURL,
                       let host = URL(string: sourceURL)?.host(percentEncoded: false) {
                        Text(host)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: LayoutDimensions.minTouchTarget)
        .padding(.vertical, Spacing.xs)
        #if os(iOS)
        .hoverEffect(.highlight)
        .draggable(item.dragURL)
        #endif
    }

    // MARK: - Helpers

    private func thumbnailImage(_ data: Data) -> Image {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #else
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #endif
        return Image(systemName: "photo")
    }
}
