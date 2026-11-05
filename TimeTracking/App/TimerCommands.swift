// TimerCommands: the main menu's Timer menu (spec_timer.md §9,
// spec_menubar.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The global timing commands, from any view (each also in the menu bar
/// item's menu), like Music's Controls menu.
struct TimerCommands: Commands {
    var host: AppHost
    @FocusedValue(\.mainWindowActive) private var windowActive
    @FocusedValue(\.timerViewActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var state: MenuState {
        MenuState(app: app, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    /// What ⌘O starts from a section's selection.
    private var sectionTarget: SectionContinueTarget? {
        state.sectionKey ? app?.sections.continueTarget : nil
    }

    var body: some Commands {
        CommandMenu("Timer") {
            Button("New Entry") {
                // In the key window's Timer, else the Mini Timer if it is
                // open, else the main window's Timer.
                run { await $0.newEntry(in: $0.activeTimer) }
            }
            .keyboardShortcut("n")
            // The selection in the view shown: "Start Timer" on a project.
            Button(sectionTarget == .project ? "Start Timer" : "Continue") {
                run { [state] in await $0.continueCommand(timerKey: state.timerKey, sectionKey: state.sectionKey) }
            }
            .keyboardShortcut("o")
            .disabled(app?.timer.mostRecentOther == nil && app?.activeTimer.list.selection == nil && sectionTarget == nil)
            Button("Stop") { run { await $0.timer.stop() } }
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
