// PlaceholderWidget: keeps the widget bundle non-empty until the running-entry,
// recent-entries, and pinned-projects widgets exist (spec_ios.md).

import SwiftUI
import WidgetKit

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "placeholder", provider: PlaceholderProvider()) { _ in
            Text("TimeTracking")
        }
        .configurationDisplayName("TimeTracking")
        .supportedFamilies([.systemSmall])
    }
}

nonisolated struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in _: Context) -> Entry {
        Entry(date: .now)
    }

    // swiftlint:disable unneeded_escaping - the TimelineProvider requirements declare @escaping
    func getSnapshot(in _: Context, completion: @escaping @Sendable (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
    // swiftlint:enable unneeded_escaping
}
