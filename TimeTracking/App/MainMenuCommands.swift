// MainMenuCommands: the Mac app's main menu, with Edit › Find and the
// Window menu's items (spec_timer_window.md §9, spec_planner_projects.md §1.2).

import SwiftUI
import TimeTrackingCore

/// Every command of the main menu. The app attaches it once, in place of
/// the Window scenes' own Window menu items (which would list the Timer
/// and the Planner a second time).
struct MainMenuCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var app: AppModel? {
        host.model
    }

    private var state: MenuState {
        MenuState(host: host, timerKey: timerActive ?? false, plannerKey: plannerActive ?? false)
    }

    var body: some Commands {
        // The app has no documents; Timer › New is ⌘N.
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .textEditing) {
            Button("Find") { find() }
                .contextCommand(KeyboardShortcut("f"), enabled: state.findCommand)
        }
        ViewCommands(host: host)
        TimerCommands(host: host)
        EntryCommands(host: host)
        PlannerCommands(host: host)
        CommandGroup(before: .windowList) {
            showTimerButton
            Button("Planner") { app?.router?.openPlanner() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
        }
    }

    /// Window › Timer Window displays the recorded show/hide shortcut.
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
        if state.timerKey {
            app.list.showFilter()
        } else if state.reportCommands {
            app.planner.reports.focusTaskFilter()
        } else if state.projectCommands {
            app.planner.projects.focusSearch()
        }
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
