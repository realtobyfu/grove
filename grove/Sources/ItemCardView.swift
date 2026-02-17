import SwiftUI

struct ItemCardView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video thumbnail
            if item.type == .video, let thumbnailData = item.thumbnail,
               let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 100)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 2)
                    )
            }

            // Type icon and title
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.metadata["isAIGenerated"] == "true" {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                            Text("AI Synthesis")
                                .font(.caption2)
                        }
                        .foregroundStyle(.purple)
                    }

                    // Video duration badge
                    if item.type == .video, let durationStr = item.metadata["videoDuration"],
                       let duration = Double(durationStr) {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8))
                            Text(duration.formattedTimestamp)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Badges row
            HStack(spacing: 12) {
                let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
                if connectionCount > 0 {
                    Label("\(connectionCount)", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let annotationCount = item.annotations.count
                if annotationCount > 0 {
                    Label("\(annotationCount)", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if item.metadata["videoLocalFile"] == "true" {
                    Text("Local Video")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let url = item.sourceURL {
                    Text(domainFrom(url))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
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
