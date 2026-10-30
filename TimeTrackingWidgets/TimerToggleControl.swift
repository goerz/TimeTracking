// TimerControls: the Control Center timer toggle and the project control,
// for example on the Action button (spec_ios.md §5).

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

/// Shares the widgets' resolver, so the control follows a push without its own token.
nonisolated struct TimerValueProvider: ControlValueProvider {
    var previewValue: WidgetControlValue {
        WidgetControlValue(isRunning: false, label: "Tracking")
    }

    func currentValue() async -> WidgetControlValue {
        await WidgetEnvironment().snapshot().control
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
