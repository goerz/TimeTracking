// PinnedWidget: buttons that start pinned projects; the running project's
// button stops it (spec_ios.md §3.4).

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

struct PinnedWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.pinned,
            intent: PinnedProjectsConfigurationIntent.self,
            provider: PinnedProvider()
        ) { entry in
            PinnedWidgetView(snapshot: entry.snapshot)
                .widgetURL(WidgetLinks.show)
        }
        .configurationDisplayName("Pinned")
        .description("Start a pinned project with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .pushHandler(TimeTrackingWidgetPushHandler.self)
    }
}

nonisolated struct PinnedProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetEnvironment.placeholder)
    }

    func snapshot(for configuration: PinnedProjectsConfigurationIntent, in context: Context) async -> SnapshotEntry {
        guard !context.isPreview else {
            return placeholder(in: context)
        }
        let snapshot = await WidgetEnvironment().snapshot(pinnedIDs: configuration.projectIDs, taskMode: mode(configuration))
        return SnapshotEntry(date: snapshot.date, snapshot: snapshot)
    }

    func timeline(for configuration: PinnedProjectsConfigurationIntent, in _: Context) async -> Timeline<SnapshotEntry> {
        await WidgetEnvironment().timeline(pinnedIDs: configuration.projectIDs, taskMode: mode(configuration))
    }

    private func mode(_ configuration: PinnedProjectsConfigurationIntent) -> PinnedTaskMode {
        configuration.task.mode(setting: DeviceSettings(identity: AppIdentity.main)[.pinnedTaskMode])
    }
}

struct PinnedWidgetView: View {
    var snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    /// Buttons per family: 2, 4, 8, 12.
    private var capacity: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 4
        case .systemLarge: 8
        default: 12
        }
    }

    private var columns: [GridItem] {
        let count = family == .systemSmall ? 1 : (family == .systemExtraLarge ? 3 : 2)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        Group {
            if snapshot.needsSetup {
                SetupNotice()
            } else if snapshot.pinned.isEmpty {
                Text("Pin projects in TimeTracking's Settings").font(.footnote).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(snapshot.pinned.prefix(capacity)) { button in
                        PinnedButtonView(button: button, stopIntent: snapshot.stopIntent)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

struct PinnedButtonView: View {
    var button: WidgetSnapshot.PinnedButton
    var stopIntent: WidgetStopIntent

    var body: some View {
        Group {
            if button.isRunning {
                Button(intent: stopIntent) { label }
            } else {
                Button(intent: WidgetStartIntent(project: button.projectID, task: button.task)) { label }
                    .disabled(button.isArchived)
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        HStack(spacing: 8) {
            WidgetAreaDot(color: button.areaColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(button.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if button.isArchived {
                    Text("Archived").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 2)
            if button.isRunning {
                Image(systemName: "stop.circle.fill").foregroundStyle(Color.stopRed).accessibilityLabel("Stop")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(button.isRunning ? Color(hex: button.areaColor ?? "#808080").opacity(0.18) : Color(uiColor: .secondarySystemFill))
        )
        .opacity(button.isArchived ? 0.5 : 1)
    }
}
