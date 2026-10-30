// PomodoroControl: the Pomodoro menu button and the pending confirmation
// (spec_timer_window.md §5.1).

import SwiftUI
import TimeTrackingCore

/// "Pomodoro" or the phase with its countdown; a prominent default button
/// replaces it while a confirmation is pending (⌘↩ confirms).
struct PomodoroControl: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let title = app.pomodoro.pomodoro.confirmationTitle, let action = app.pomodoro.pomodoro.nextPhaseAction {
            Button(title) {
                app.perform(action)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("timer.pomodoroConfirm")
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Menu {
                    menuItems
                } label: {
                    Label(app.pomodoro.pomodoro.buttonTitle(at: app.clock.now), systemImage: "timer")
                        .monospacedDigit()
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize()
                .accessibilityIdentifier("timer.pomodoroButton")
            }
        }
    }

    @ViewBuilder private var menuItems: some View {
        let isRunning = app.timer.isRunning
        if app.pomodoro.state.isOn {
            ForEach(app.pomodoro.actions(isRunning: isRunning), id: \.self) { action in
                Button(action.title) { app.perform(action) }
            }
        } else {
            Button("Start Pomodoro (\(app.pomodoro.focusMinutes) min)") { app.perform(.start) }
                .disabled(!isRunning)
        }
        Divider()
        Button("Pomodoro Settings…") { app.router?.openSettings(pane: .pomodoro) }
    }
}
