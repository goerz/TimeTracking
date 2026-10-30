// TimerToggleControl: the Control Center timer toggle and its value provider
// (spec_ios.md §5).

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
