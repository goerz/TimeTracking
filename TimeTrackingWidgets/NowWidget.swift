// NowWidget: the running entry widget on the Home Screen and the Lock
// Screen (spec_ios.md §3.2, §3.5).

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.now, provider: SnapshotProvider()) { entry in
            NowWidgetView(snapshot: entry.snapshot)
                .widgetURL(WidgetLinks.show)
        }
        .configurationDisplayName("Now")
        .description("The running entry, or the latest one to continue.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .pushHandler(TimeTrackingWidgetPushHandler.self)
    }
}

/// `timetracking://show`, the tap outside a button (spec_ios.md §3.1).
enum WidgetLinks {
    static var show: URL? {
        URL(string: "\(AppIdentity.main?.urlScheme ?? "timetracking")://show")
    }
}

struct NowWidgetView: View {
    var snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetBackground()
    }

    @ViewBuilder private var content: some View {
        if snapshot.needsSetup {
            SetupNotice()
        } else {
            switch family {
            case .systemMedium: NowMedium(snapshot: snapshot)
            case .accessoryInline: NowInline(snapshot: snapshot)
            case .accessoryCircular: NowCircular(snapshot: snapshot)
            case .accessoryRectangular: NowRectangular(snapshot: snapshot)
            default: NowSmall(snapshot: snapshot)
            }
        }
    }
}

/// "Today" and the day's total, live while an entry runs.
struct TodayTotal: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Text("Today")
            if let start = snapshot.todayTimerStart {
                LiveTimer(start: start)
            } else {
                Text(DurationText.clock(snapshot.todayStoppedSeconds)).monospacedDigit()
            }
        }
    }
}

struct NowSmall: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let running = snapshot.running {
                ProjectLine(row: running.row, showsClient: false)
                    .font(.subheadline)
                Text(running.row.task.isEmpty ? "No task" : running.row.task)
                    .font(.headline)
                    .lineLimit(2)
                    .privacySensitive()
                Spacer(minLength: 0)
                PomodoroLine(snapshot: snapshot)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 4) {
                    LiveTimer(snapshot: snapshot)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CircleIntentButton(intent: snapshot.stopIntent, systemImage: "stop.fill", color: .stopTint)
                }
            } else {
                Text("Not tracking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let latest = snapshot.latest {
                    Text(latest.task.isEmpty ? "No task" : latest.task)
                        .font(.headline)
                        .lineLimit(2)
                        .privacySensitive()
                    ProjectLine(row: latest, showsClient: false)
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 4) {
                    TodayTotal(snapshot: snapshot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CircleIntentButton(intent: snapshot.continueIntent, systemImage: "play.fill", color: .startTint)
                }
            }
        }
    }
}

struct NowMedium: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let running = snapshot.running {
                runningContent(running)
            } else {
                idleContent
            }
            ForEach(snapshot.macLines, id: \.self) { line in
                Label(line, systemImage: "desktopcomputer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func runningContent(_ running: WidgetSnapshot.Running) -> some View {
        Text(running.row.task.isEmpty ? "No task" : running.row.task)
            .font(.headline)
            .lineLimit(snapshot.macLines.isEmpty ? 2 : 1)
            .privacySensitive()
        ProjectLine(row: running.row)
            .font(.subheadline)
            .padding(.top, 2)
        Spacer(minLength: 4)
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                LiveTimer(snapshot: snapshot)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    TodayTotal(snapshot: snapshot)
                    PomodoroLine(snapshot: snapshot)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CircleIntentButton(intent: snapshot.stopIntent, systemImage: "stop.fill", color: .stopTint)
        }
    }

    @ViewBuilder private var idleContent: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Not tracking")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TodayTotal(snapshot: snapshot)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        Spacer(minLength: 4)
        if let latest = snapshot.latest {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(latest.task.isEmpty ? "No task" : latest.task)
                        .font(.headline)
                        .lineLimit(1)
                        .privacySensitive()
                    ProjectLine(row: latest)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CircleIntentButton(intent: snapshot.continueIntent, systemImage: "play.fill", color: .startTint)
            }
        }
    }
}

struct NowInline: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        if let running = snapshot.running {
            let elapsed = Text(timerInterval: snapshot.elapsedTimer ?? running.chainStart ... running.chainStart, countsDown: false)
            Label {
                Text("\(elapsed) · \(running.row.projectName ?? "No project")")
            } icon: {
                Image(systemName: "stopwatch")
            }
        } else {
            Label("Not tracking", systemImage: "stopwatch")
        }
    }
}

struct NowCircular: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if snapshot.running != nil {
                Button(intent: snapshot.stopIntent) {
                    VStack(spacing: 1) {
                        Image(systemName: "stop.fill")
                            .font(.body)
                            .widgetAccentable()
                            .accessibilityLabel("Stop")
                        LiveTimer(snapshot: snapshot)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: snapshot.continueIntent) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .widgetAccentable()
                        .accessibilityLabel("Continue")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NowRectangular: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                if let running = snapshot.running {
                    Text(running.row.task.isEmpty ? "No task" : running.row.task)
                        .font(.headline)
                        .lineLimit(1)
                        .privacySensitive()
                    Text(running.row.projectName ?? "No project")
                        .lineLimit(1)
                    LiveTimer(snapshot: snapshot)
                        .font(.headline)
                        .widgetAccentable()
                } else {
                    Text("Not tracking")
                        .font(.headline)
                    Text(snapshot.latest?.task ?? "")
                        .lineLimit(2)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if snapshot.running != nil {
                Button(intent: snapshot.stopIntent) { glyph("stop.circle.fill", label: "Stop") }
                    .buttonStyle(.plain)
            } else {
                Button(intent: snapshot.continueIntent) { glyph("play.circle.fill", label: "Continue") }
                    .buttonStyle(.plain)
            }
        }
    }

    private func glyph(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.title)
            .widgetAccentable()
            .accessibilityLabel(label)
    }
}
