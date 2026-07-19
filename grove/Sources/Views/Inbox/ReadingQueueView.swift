import SwiftUI
import SwiftData

/// Ordered list of items deferred with "Read Later", soonest return first.
/// Rows are quiet and monochrome: title, source, and when the item returns
/// to the inbox, with inline actions to read now or return it immediately.
struct ReadingQueueView: View {
    /// Queued items, expected sorted by `readLaterUntil` ascending.
    let items: [Item]
    /// Restore the item to the inbox and open it for reading.
    let onReadNow: (Item) -> Void
    /// Restore the item to the inbox without opening it.
    let onReturnToInbox: (Item) -> Void

    /// Defensive re-sort so ordering holds even if the caller passes raw results.
    private var orderedItems: [Item] {
        items.sorted { ($0.readLaterUntil ?? .distantFuture) < ($1.readLaterUntil ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(orderedItems) { item in
                queueRow(for: item)
                if item.id != orderedItems.last?.id {
                    Divider()
                        .padding(.leading, 34)
                }
            }
        }
    }

    // MARK: - Row

    private func queueRow(for item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(sourceLabel(for: item))
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)

                    if let until = item.readLaterUntil {
                        Text("\u{00B7}")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                        Text(returnLabel(for: until))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: Spacing.sm)

            Button {
                onReadNow(item)
            } label: {
                Text("Read now")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Move back to inbox and open")

            Button {
                onReturnToInbox(item)
            } label: {
                Text("To inbox")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Move back to inbox now")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Labels

    /// Source domain for links, otherwise the item type.
    private func sourceLabel(for item: Item) -> String {
        if let url = item.sourceURL, !url.isEmpty {
            return domainFrom(url)
        }
        switch item.type {
        case .article: return "Article"
        case .codebase: return "Codebase"
        case .video: return "Video"
        case .note: return "Note"
        case .courseLecture: return "Course lecture"
        }
    }

    /// Human-readable return time. Reuses the Read Later preset labels when the
    /// scheduled date still matches a preset, otherwise falls back to the same
    /// abbreviated formatting used by the queued summary.
    private func returnLabel(for date: Date) -> String {
        if let preset = ReadLaterPreset.allCases.first(where: {
            Calendar.current.isDate($0.scheduledDate(), equalTo: date, toGranularity: .minute)
        }) {
            return "Returns \(preset.label.lowercased())"
        }
        return "Returns \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
