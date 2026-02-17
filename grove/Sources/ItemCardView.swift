import SwiftUI

struct ItemCardView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type icon and title
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)

                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                if let url = item.sourceURL {
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
