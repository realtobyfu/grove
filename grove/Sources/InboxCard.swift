import SwiftUI

struct InboxCard: View {
    let item: Item
    let isSelected: Bool
    let onKeep: () -> Void
    let onLater: () -> Void
    let onDrop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: type icon + title
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)

                    // Source domain and capture date
                    HStack(spacing: 8) {
                        if let url = item.sourceURL, !url.isEmpty {
                            Label(domainFrom(url), systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(item.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            // Content preview if available
            if let content = item.content, !content.isEmpty {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Auto-tags
            if !item.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tags.prefix(5)) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    if item.tags.count > 5 {
                        Text("+\(item.tags.count - 5)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onKeep()
                } label: {
                    Label("Keep", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button {
                    onLater()
                } label: {
                    Label("Later", systemImage: "clock")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onDrop()
                } label: {
                    Label("Drop", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)

                Spacer()

                // Keyboard hint
                HStack(spacing: 6) {
                    keyHint("1", label: "Keep")
                    keyHint("2", label: "Later")
                    keyHint("3", label: "Drop")
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(lineWidth: isSelected ? 2 : 1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.blue) : AnyShapeStyle(.quaternary))
        )
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))

            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func domainFrom(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
