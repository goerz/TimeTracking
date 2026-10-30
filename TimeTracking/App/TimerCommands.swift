// TimerCommands: the main menu's Timer, Edit, View, and Window commands
// (spec_timer_window.md §9, spec_menubar.md §2.2).

import SwiftUI
import TimeTrackingCore

/// "Timer key" commands are enabled only while the Timer window is key.
struct TimerCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var app: AppModel? {
        host.model
    }

    private var timerKey: Bool {
        timerActive ?? false
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
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
            Button("Set Project…") { app?.openChipPicker() }
                .keyboardShortcut("p")
                .disabled(!timerKey)
            Button("Edit Entry…") { app?.editEntry() }
                .keyboardShortcut("e")
                .disabled(!timerKey)
            Button("Delete Entry…") {
                if let app {
                    app.timer.alert = app.list.deleteAlert()
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!timerKey || app?.list.selection == nil || app?.presentation.listFocused != true)
            Divider()
            pomodoroCommands
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { find() }
                .keyboardShortcut("f")
                .disabled(!timerKey && plannerActive != true)
        }
        CommandGroup(before: .toolbar) {
            Toggle("Compact Mode", isOn: Binding(
                get: { app?.window?.isCompact ?? false },
                set: { _ in app?.toggleCompact() }
            ))
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!timerKey)
            Toggle("Float on Top", isOn: Binding(
                get: { app?.settings.timerPinned ?? false },
                set: { app?.setPinned($0) }
            ))
            .disabled(!timerKey)
            Button("Scroll to Today") { app?.list.scrollToTop() }
                .keyboardShortcut(.upArrow)
                .disabled(!timerKey)
            Divider()
        }
        CommandGroup(before: .windowList) {
            showTimerButton
            Button("Planner") { app?.router?.openPlanner() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
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

    /// Window > Timer Window displays the recorded show/hide shortcut.
    @ViewBuilder private var showTimerButton: some View {
        let button = Button("Timer Window") { app?.router?.showTimer(focusTask: false) }
        if let key = app?.showHideKey, let character = key.key.first {
            button.keyboardShortcut(KeyEquivalent(character), modifiers: key.eventModifiers)
        } else {
            button
        }
    }

    /// ⌘F: the Timer list's filter, or the Planner section's search field.
    private func find() {
        guard let app else {
            return
        }
        if timerKey {
            app.list.showFilter()
        } else if app.planner.section == .reports {
            app.planner.reports.focusTaskFilter()
        } else if app.planner.section == .projects {
            app.planner.projects.focusSearch()
        }
    }

    private func run(_ action: @escaping @MainActor (AppModel) async -> Void) {
        guard let app else {
            return
        }
        Task { await action(app) }
    }
}

extension MenuKey {
    /// The SwiftUI modifiers.
    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) {
            result.insert(.command)
        }
        if modifiers.contains(.shift) {
            result.insert(.shift)
        }
        if modifiers.contains(.option) {
            result.insert(.option)
        }
        if modifiers.contains(.control) {
            result.insert(.control)
        }
        return result
    }
}
