// PomodoroDurationRows: the focus and break steppers of the Pomodoro
// settings (spec_timer_window.md §5.2, spec_ios.md §2.9).

import SwiftUI
import TimeTrackingCore

/// The two synced durations as stepper rows; the titles differ by platform.
struct PomodoroDurationRows: View {
    let pomodoro: PomodoroDriver
    var focusTitle: String
    var breakTitle: String

    var body: some View {
        row(focusTitle, minutes: pomodoro.focusMinutes, key: .pomodoroFocusMinutes) { value in
            await pomodoro.setFocusMinutes(value)
        }
        #if os(macOS)
        .accessibilityIdentifier("settings.focusMinutes")
        #endif
        row(breakTitle, minutes: pomodoro.breakMinutes, key: .pomodoroBreakMinutes) { value in
            await pomodoro.setBreakMinutes(value)
        }
    }

    @ViewBuilder
    private func row(
        _ title: String,
        minutes: Int,
        key: SyncedSettingKey<Int>,
        set: @escaping (Int) async -> Void
    ) -> some View {
        let amount = Binding {
            minutes
        } set: { value in
            Task { await set(value) }
        }
        #if os(macOS)
            StepperRow(title: title, value: "\(minutes) min", amount: amount, range: key.range)
        #else
            Stepper(value: amount, in: key.range) {
                LabeledContent(title, value: "\(minutes) min")
            }
        #endif
    }
}
