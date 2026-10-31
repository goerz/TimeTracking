// TimerCommands: the main menu's Timer menu (spec_timer_window.md §9,
// spec_menubar.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The running timer and the Pomodoro, from any window: each item is also
/// in the menu bar item's menu.
struct TimerCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var timerKey: Bool {
        timerActive ?? false
    }

    var body: some Commands {
        CommandMenu("Timer") {
            Button("New") { run { await $0.newEntry() } }
                .keyboardShortcut("n")
            Button("Continue") { run { [timerKey] in await $0.continueCommand(timerKey: timerKey) } }
                .keyboardShortcut("o")
                .disabled(app?.timer.mostRecentOther == nil && app?.list.selection == nil)
            Button("Stop") { run { await $0.stopEntry() } }
                .keyboardShortcut("s")
                .disabled(app?.timer.isRunning != true)
            Button("Discard Running Entry") { run { await $0.timer.requestDiscard(skipAlert: false) } }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(app?.timer.isRunning != true)
            Divider()
            pomodoroCommands
        }
    }

    /// Start/Cancel Pomodoro, and the next step titled by what it does.
    @ViewBuilder private var pomodoroCommands: some View {
        Button(app?.pomodoro.state.isOn == true ? "Cancel Pomodoro" : "Start Pomodoro") {
            if let app {
                app.pomodoro.toggle(isRunning: app.timer.isRunning)
            }
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(app?.pomodoro.state.isOn != true && app?.timer.isRunning != true)
        // "End Focus Now", "Start Break", "End Break Now", or "Start Focus";
        // disabled under the first while the Pomodoro is off.
        Button(app?.pomodoro.pomodoro.nextPhaseAction?.title ?? PomodoroAction.endFocusNow.title) {
            if let app {
                app.pomodoro.nextPhase(isRunning: app.timer.isRunning)
            }
        }
        .keyboardShortcut("p", modifiers: [.command, .control])
        .disabled(app?.pomodoro.pomodoro.nextPhaseAction == nil)
    }

    private func run(_ action: @escaping @MainActor (AppModel) async -> Void) {
        guard let app else {
            return
        }
        Task { await action(app) }
    }
}
