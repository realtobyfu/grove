import SwiftUI

struct SuggestedArticleCard: View {
    let item: Item
    let score: Double
    let onAdd: () -> Void
    let onDismiss: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    private var domain: String {
        item.metadata["feedSourceDomain"] ?? domainFromURL ?? ""
    }

    private var domainFromURL: String? {
        guard let urlString = item.sourceURL,
              let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var publishDateText: String? {
        guard let dateString = item.metadata["publishedAt"],
              let date = ISO8601DateFormatter().date(from: dateString) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentSelection)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text("SUGGESTED")
                        .font(.groveBadge)
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()

                    if !domain.isEmpty {
                        Text(domain)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let content = item.content, !content.isEmpty {
                    Text(content)
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: Spacing.sm) {
                    if let pubDate = publishDateText {
                        Text(pubDate)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                    }

                    if let author = item.metadata["author"], !author.isEmpty {
                        Text("by \(author)")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: Spacing.md) {
                    Button {
                        onAdd()
                    } label: {
                        Text("Add to Inbox")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textInverse)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.textPrimary)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        onOpen()
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.bgCard.opacity(0.85) : Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? Color.borderInput : Color.borderPrimary, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}
