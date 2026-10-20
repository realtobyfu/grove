import SwiftUI
import WidgetKit

struct GroveLearningEntry: TimelineEntry {
    let date: Date
    let snapshot: LearningWidgetSnapshot
}

struct GroveLearningProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroveLearningEntry {
        GroveLearningEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (GroveLearningEntry) -> Void) {
        completion(GroveLearningEntry(date: .now, snapshot: LearningWidgetSnapshotStorage.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GroveLearningEntry>) -> Void) {
        let entry = GroveLearningEntry(date: .now, snapshot: LearningWidgetSnapshotStorage.read())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct GroveLearningWidgetView: View {
    let entry: GroveLearningEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GROVE")
                .font(.custom("IBMPlexMono-Medium", size: 11, relativeTo: .caption2))
                .foregroundStyle(.secondary)

            Text("Flashcards")
                .font(.custom("Newsreader-Medium", size: family == .systemSmall ? 21 : 25, relativeTo: .title2))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Text(entry.snapshot.hasCards ? "Review" : "Open Grove")
                    .font(.custom("IBMPlexSans-Medium", size: 13, relativeTo: .body))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
            }
            if family == .systemMedium, entry.snapshot.hasCards {
                Text("\(entry.snapshot.sessionMinutes) min")
                    .font(.custom("IBMPlexSans-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color.primary)
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.snapshot.reviewURL)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your learning review in Grove.")
    }
}

@main
struct GroveLearningWidget: Widget {
    let kind = "GroveLearningWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GroveLearningProvider()) { entry in
            GroveLearningWidgetView(entry: entry)
        }
        .configurationDisplayName("Flashcards")
        .description("Review saved questions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
