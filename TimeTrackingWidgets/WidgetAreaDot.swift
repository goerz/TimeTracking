// WidgetParts: the pieces the widgets share: the area dot, live timers, the
// stop and continue buttons, and the setup notice (spec_ios.md §3).

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

extension Color {
    /// The color of an `#RRGGBB` value; gray for a malformed one.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0x808080
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static let startGreen = Color(red: 0.30, green: 0.69, blue: 0.43)
    static let stopRed = Color(red: 0.87, green: 0.42, blue: 0.36)
}

/// The area dot; desaturated in the accented rendering mode.
struct WidgetAreaDot: View {
    var color: String?
    var size: CGFloat = 9

    var body: some View {
        if let color {
            Circle().fill(Color(hex: color)).frame(width: size, height: size).widgetAccentable()
        } else {
            Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: size, height: size)
        }
    }
}

/// An elapsed time counting up from `start`.
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

/// The round Stop or Continue button.
struct CircleIntentButton<Intent: AppIntent>: View {
    var intent: Intent
    var systemImage: String
    var color: Color
    var diameter: CGFloat = 36

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage).accessibilityLabel(systemImage == "stop.fill" ? "Stop" : "Start")
                .font(.system(size: diameter * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(color))
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

/// "Open TimeTracking to finish setup" before the first sync.
struct SetupNotice: View {
    var body: some View {
        Text("Open TimeTracking to finish setup")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// The project and client line.
struct ProjectLine: View {
    var row: WidgetSnapshot.Row
    var showsClient = true

    var body: some View {
        HStack(spacing: 5) {
            WidgetAreaDot(color: row.areaColor)
            Text(row.projectName ?? "No project").lineLimit(1)
            if showsClient, let client = row.clientName {
                Text("· \(client)").foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
