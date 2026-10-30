// TimerControls: the Control Center timer toggle and the project control,
// for example on the Action button (spec_ios.md §5).

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

/// The toggle's value: running, and the label while on.
struct TimerControlValue: Sendable {
    var isRunning: Bool
    /// The running task, else the project name, else "Tracking".
    var label: String
}

/// Shares the widgets' resolver, so the control follows a push without its own token.
nonisolated struct TimerValueProvider: ControlValueProvider {
    var previewValue: TimerControlValue {
        TimerControlValue(isRunning: false, label: "Tracking")
    }

    func currentValue() async -> TimerControlValue {
        let snapshot = await WidgetEnvironment().snapshot()
        guard let running = snapshot.running else {
            return TimerControlValue(isRunning: false, label: "Start")
        }
        let label = running.row.task.isEmpty ? (running.row.projectName ?? "Tracking") : running.row.task
        return TimerControlValue(isRunning: true, label: label)
    }
}

struct TimerToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.timerToggle, provider: TimerValueProvider()) { value in
            ControlWidgetToggle("Timer", isOn: value.isRunning, action: ToggleTimerIntent()) { isOn in
                Label(isOn ? value.label : "Start", systemImage: isOn ? "stop.fill" : "play.fill")
                    .privacySensitive()
                    .controlWidgetActionHint(isOn ? "Stop tracking" : "Continue latest entry")
            }
        }
        .displayName("Timer")
        .description("Continue the latest entry, or stop the running one.")
    }
}

struct StartProjectControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WidgetKind.startProject, intent: StartProjectConfiguration.self) { configuration in
            ControlWidgetButton(action: WidgetStartIntent(project: configuration.project?.projectID, task: "")) {
                Label(configuration.project?.name ?? "Start Project", systemImage: "play.fill")
            }
        }
        .displayName("Start Project")
        .description("Starts the project you choose.")
        .promptsForUserConfiguration()
    }
}
