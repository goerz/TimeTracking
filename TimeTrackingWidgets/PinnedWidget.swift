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

    /// Columns per family: 1, 2, 2, 3; the rows fill the height, so a
    /// family's buttons have one size however many are pinned.
    private var columns: Int {
        family == .systemSmall ? 1 : (family == .systemExtraLarge ? 3 : 2)
    }

    private var grid: some View {
        let buttons = Array(snapshot.pinned.prefix(capacity))
        return VStack(spacing: 8) {
            ForEach(0 ..< capacity / columns, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < buttons.count {
                            PinnedButtonView(button: buttons[index], action: snapshot.action(of: buttons[index]))
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        Group {
            if snapshot.needsSetup {
                SetupNotice()
            } else if snapshot.pinned.isEmpty {
                WidgetNotice(
                    systemImage: SymbolName.pin,
                    title: "No Pinned Projects",
                    message: family == .systemSmall ? nil : "Add projects under Pinned projects in the app's Settings."
                )
            } else {
                grid
            }
        }
        .widgetBackground()
    }
}

struct PinnedButtonView: View {
    var button: WidgetSnapshot.PinnedButton
    /// `WidgetSnapshot.action(of:)`.
    var action: WidgetAction

    var body: some View {
        Group {
            if case let .stop(expected) = action {
                Button(intent: WidgetStopIntent(entry: expected)) { label }
            } else {
                Button(intent: WidgetStartIntent(project: button.projectID, task: button.task)) { label }
                    .disabled(button.isArchived)
            }
        }
        .buttonStyle(.plain)
    }

    /// Area dot and project; the running project's button carries the stop
    /// circle and the area color's tint.
    private var label: some View {
        HStack(spacing: 8) {
            WidgetAreaDot(color: button.areaColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(button.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if button.isArchived {
                    Text("Archived").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if button.isRunning {
                CircleGlyph(systemImage: SymbolName.stop, color: .stopTint, diameter: 24)
                    .accessibilityLabel("Stop")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
        .background(background)
        .opacity(button.isArchived ? 0.5 : 1)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(button.isRunning ? AnyShapeStyle(Color(hex: button.areaColor ?? "#808080").opacity(0.2)) : AnyShapeStyle(.fill.secondary))
    }
}
