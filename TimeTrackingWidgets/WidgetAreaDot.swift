// WidgetAreaDot and the other pieces the widgets share: the metrics, live
// timers, the start and stop circles, the Pomodoro line, the empty notices,
// and the project line (ios.md §3, design.md §6, §7). The extension
// does not compile `Shared/`, so it keeps its own copy of the start and stop
// tints.

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

extension Color {
    /// The color of an `#RRGGBB` value, parsed by `AreaColor`; gray for a
    /// malformed one (`Shared/Design/Color+Hex.swift`).
    init(hex: String) {
        let color = (try? AreaColor(hex)) ?? AreaColor(red: UInt8(0x80), green: 0x80, blue: 0x80)
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }

    /// Start and continue (`Shared/Design/Design.swift`).
    static let startTint = Color.green
    /// Stop.
    static let stopTint = Color.red
}

/// Widget sizes (design.md §7 at widget scale).
enum WidgetMetrics {
    /// The start and stop circle of the Now widget.
    static let button: CGFloat = 44
    /// The circles of Recent rows.
    static let rowButton: CGFloat = 32
    /// The area dot.
    static let dot: CGFloat = 8
}

/// The 8 pt area dot; desaturated in the accented rendering mode.
struct WidgetAreaDot: View {
    var color: String?
    var size: CGFloat = WidgetMetrics.dot

    var body: some View {
        if let color {
            Circle().fill(Color(hex: color)).frame(width: size, height: size).widgetAccentable()
        } else {
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: size, height: size)
        }
    }
}

/// An elapsed time counting up (the system live timer: `m:ss`, `h:mm:ss` from one hour).
struct LiveTimer: View {
    var interval: ClosedRange<Date>?

    /// The running entry's elapsed time (`WidgetSnapshot.elapsedTimer`).
    init(snapshot: WidgetSnapshot) {
        self.interval = snapshot.elapsedTimer
    }

    /// A time counting up from `start`.
    init(start: Date) {
        self.interval = start ... Date.distantFuture
    }

    var body: some View {
        if let interval {
            Text(timerInterval: interval, countsDown: false)
                .monospacedDigit()
        }
    }
}

/// The filled start or stop circle with its glyph at 40% of the diameter.
/// In the accented and vibrant modes the glyph is cut out of the circle, so
/// the button stays one shape in the tint.
struct CircleGlyph: View {
    var systemImage: String
    var color: Color
    var diameter: CGFloat

    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let glyph = Image(systemName: systemImage)
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .accessibilityHidden(true)
        Group {
            if mode == .fullColor {
                Circle().fill(color)
                    .overlay { glyph.foregroundStyle(.white) }
            } else {
                Circle()
                    .overlay { glyph.blendMode(.destinationOut) }
                    .compositingGroup()
                    .widgetAccentable()
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The round Stop or Continue button.
struct CircleIntentButton<Intent: AppIntent>: View {
    var intent: Intent
    var systemImage: String
    /// The accessibility label.
    var label: LocalizedStringKey
    var color: Color
    var diameter: CGFloat = WidgetMetrics.button

    var body: some View {
        Button(intent: intent) {
            CircleGlyph(systemImage: systemImage, color: color, diameter: diameter)
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
    }
}

extension WidgetSnapshot {
    /// The Stop button's intent for the running entry.
    var stopIntent: WidgetStopIntent {
        if case let .stop(expected) = primaryAction {
            return WidgetStopIntent(entry: expected)
        }
        return WidgetStopIntent(entry: nil)
    }

    /// The Continue button's intent for the latest entry.
    var continueIntent: WidgetContinueIntent {
        WidgetContinueIntent(entry: latestEntryID)
    }
}

/// The Pomodoro of this device as the phase glyph and the countdown, or
/// `+` and the time since the phase ended (design.md §2).
struct PomodoroLine: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        if let end = snapshot.pomodoro.phaseEnd {
            Label {
                if snapshot.pomodoro.isPendingConfirmation {
                    Text("+\(Text(timerInterval: end ... Date.distantFuture, countsDown: false))")
                } else {
                    Text(timerInterval: snapshot.date ... max(end, snapshot.date), countsDown: true)
                }
            } icon: {
                // The focus glyph is the app's apple symbol (a copy in this
                // target's asset catalog).
                (snapshot.pomodoro.isFocusPhase ? Image(.pomodoro) : Image(systemName: SymbolName.pomodoroBreak))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
            }
            .monospacedDigit()
        }
    }
}

/// A centered symbol, title, and explanation for a widget without content.
struct WidgetNotice: View {
    var systemImage: String
    var title: String
    var message: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Open <app name> to finish setting up" before the first sync.
struct SetupNotice: View {
    var body: some View {
        WidgetNotice(systemImage: SymbolName.iCloudDownload, title: "Open \(AppDisplayName.orGeneric) to finish setting up")
    }
}

/// The area dot, the project, and " · client" in the secondary color.
struct ProjectLine: View {
    var row: WidgetSnapshot.Row
    var showsClient = true

    var body: some View {
        HStack(spacing: 4) {
            WidgetAreaDot(color: row.areaColor)
            Group {
                if showsClient, let client = row.clientName {
                    Text("\(row.projectText)\(Text(" · \(client)").foregroundStyle(.secondary))")
                } else {
                    Text(row.projectText)
                }
            }
            .lineLimit(1)
        }
    }
}

extension WidgetSnapshot.Row {
    /// The task, or "No task".
    var taskText: String {
        task.isEmpty ? "No task" : task
    }

    /// The project's name, or "No project".
    var projectText: String {
        projectName ?? "No project"
    }
}

extension View {
    /// The widgets' background: the system background, removed by the
    /// system in StandBy, on the Lock Screen, and in the tinted modes.
    func widgetBackground() -> some View {
        containerBackground(.background, for: .widget)
    }
}
