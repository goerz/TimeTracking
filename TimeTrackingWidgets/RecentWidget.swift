// RecentWidget: the running entry and recent (task, project) pairs with
// Continue buttons (spec_ios.md §3.3).

import SwiftUI
import TimeTrackingCore
import WidgetKit

struct RecentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.recent, provider: SnapshotProvider()) { entry in
            RecentWidgetView(snapshot: entry.snapshot)
                .widgetURL(WidgetLinks.show)
        }
        .configurationDisplayName("Recent")
        .description("Continue a recent task with one tap.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
        .pushHandler(TimeTrackingWidgetPushHandler.self)
    }
}

struct RecentWidgetView: View {
    var snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    /// Rows per column: medium 3, large 7, extra large two columns of 7.
    private var rowsPerColumn: Int {
        family == .systemMedium ? 3 : 7
    }

    private var columns: Int {
        family == .systemExtraLarge ? 2 : 1
    }

    var body: some View {
        Group {
            if snapshot.needsSetup {
                SetupNotice()
            } else if snapshot.running == nil, snapshot.recent.isEmpty {
                WidgetNotice(systemImage: "stopwatch", title: "No Recent Entries", message: "Entries you track appear here.")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows(column: column).enumerated()), id: \.offset) { index, row in
                                if index > 0 {
                                    Divider()
                                }
                                row.frame(maxHeight: .infinity)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .widgetBackground()
    }

    private func rows(column: Int) -> [AnyView] {
        var all: [AnyView] = []
        if let running = snapshot.running {
            all.append(AnyView(RecentRow(row: running.row) {
                LiveTimer(snapshot: snapshot)
                    .font(.subheadline.weight(.medium))
                    .fixedSize()
                CircleIntentButton(
                    intent: snapshot.stopIntent,
                    systemImage: "stop.fill",
                    color: .stopTint,
                    diameter: WidgetMetrics.rowButton
                )
            }))
        }
        for row in snapshot.recent {
            all.append(AnyView(RecentRow(row: row) {
                CircleIntentButton(
                    intent: WidgetStartIntent(project: row.projectID, task: row.task),
                    systemImage: "play.fill",
                    color: .startTint,
                    diameter: WidgetMetrics.rowButton
                )
            }))
        }
        let start = column * rowsPerColumn
        guard start < all.count else {
            return []
        }
        return Array(all[start ..< min(start + rowsPerColumn, all.count)])
    }
}

/// Task over the area dot and project, with trailing controls.
struct RecentRow<Trailing: View>: View {
    var row: WidgetSnapshot.Row
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.task.isEmpty ? "No task" : row.task)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .privacySensitive()
                ProjectLine(row: row, showsClient: false)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}
