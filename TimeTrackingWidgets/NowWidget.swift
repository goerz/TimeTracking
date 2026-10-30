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
            .containerBackground(for: .widget) {
                Color(uiColor: .systemBackground)
            }
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

struct NowSmall: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let running = snapshot.running {
                ProjectLine(row: running.row, showsClient: false).font(.headline)
                Text(running.row.task).lineLimit(2).privacySensitive()
                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    LiveTimer(snapshot: snapshot).font(.system(size: 28, weight: .semibold))
                    Spacer(minLength: 4)
                    CircleIntentButton(intent: snapshot.stopIntent, systemImage: "stop.fill", color: .stopRed, diameter: 40)
                }
            } else {
                Text("Not tracking").font(.headline).foregroundStyle(.secondary)
                if let latest = snapshot.latest {
                    Text(latest.task).lineLimit(2).privacySensitive()
                    ProjectLine(row: latest, showsClient: false).font(.subheadline)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    CircleIntentButton(intent: snapshot.continueIntent, systemImage: "play.fill", color: .startGreen, diameter: 40)
                }
            }
        }
    }
}

struct NowMedium: View {
    var snapshot: WidgetSnapshot

    private func runningContent(_ running: WidgetSnapshot.Running) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(running.row.task.isEmpty ? "No task" : running.row.task).font(.headline).lineLimit(1).privacySensitive()
                Spacer()
                LiveTimer(snapshot: snapshot).font(.title2.weight(.semibold))
            }
            ProjectLine(row: running.row)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    todayLine
                    pomodoroLine
                }
                Spacer()
                CircleIntentButton(intent: snapshot.stopIntent, systemImage: "stop.fill", color: .stopRed, diameter: 44)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let running = snapshot.running {
                runningContent(running)
            } else {
                Text("Not tracking").font(.headline).foregroundStyle(.secondary)
                todayLine
                if let latest = snapshot.latest {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(latest.task).lineLimit(1).privacySensitive()
                            ProjectLine(row: latest).font(.subheadline)
                        }
                        Spacer()
                        CircleIntentButton(intent: snapshot.continueIntent, systemImage: "play.fill", color: .startGreen, diameter: 44)
                    }
                }
            }
            Spacer(minLength: 0)
            ForEach(snapshot.macLines, id: \.self) { line in
                Label(line, systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var todayLine: some View {
        HStack(spacing: 4) {
            Text("Today")
            if let start = snapshot.todayTimerStart {
                LiveTimer(start: start)
            } else {
                Text(DurationText.clock(snapshot.todayStoppedSeconds)).monospacedDigit()
            }
        }
    }

    @ViewBuilder private var pomodoroLine: some View {
        switch snapshot.pomodoro {
        case let .focus(end), let .onBreak(end):
            Label {
                let countdown = Text(timerInterval: snapshot.date ... max(end, snapshot.date), countsDown: true)
                Text("\(snapshot.pomodoro.isFocusPhase ? "Focus" : "Break") \(countdown)")
            } icon: {
                Image(systemName: "timer")
            }
            .foregroundStyle(.tint)
        case .off, .focusOver, .breakOver:
            EmptyView()
        }
    }
}

struct NowInline: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        if let running = snapshot.running {
            let elapsed = Text(timerInterval: snapshot.elapsedTimer ?? running.chainStart ... running.chainStart, countsDown: false)
            Text("▶ \(elapsed) · \(running.row.projectName ?? "TimeTracking")")
        } else {
            Text("Not tracking")
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
                    VStack(spacing: 2) {
                        Image(systemName: "stop.fill").accessibilityLabel("Stop")
                        LiveTimer(snapshot: snapshot).font(.caption2).minimumScaleFactor(0.6)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: snapshot.continueIntent) {
                    Image(systemName: "play.fill").font(.title2).accessibilityLabel("Continue")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NowRectangular: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let running = snapshot.running {
                    Text(running.row.task.isEmpty ? "No task" : running.row.task).font(.headline).lineLimit(1).privacySensitive()
                    Text(running.row.projectName ?? "No project").lineLimit(1)
                    LiveTimer(snapshot: snapshot).font(.headline)
                } else {
                    Text("Not tracking").font(.headline)
                    Text(snapshot.latest?.task ?? "").lineLimit(1).privacySensitive()
                }
            }
            Spacer(minLength: 4)
            if snapshot.running != nil {
                Button(intent: snapshot.stopIntent) {
                    Image(systemName: "stop.fill").accessibilityLabel("Stop")
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: snapshot.continueIntent) {
                    Image(systemName: "play.fill").accessibilityLabel("Continue")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
