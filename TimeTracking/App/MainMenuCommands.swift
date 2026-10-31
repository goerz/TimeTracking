// MainMenuCommands: the Mac app's main menu (experiment: one window, object
// menus). File, Edit, View, Timer, Entry, Project, Window: a fixed set, as
// in Music or Mail; Entry and Project act on what is selected in the view
// shown, and are enabled by that selection.

import SwiftUI
import TimeTrackingCore

/// Every command of the main menu.
struct MainMenuCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive

    private var app: AppModel? {
        host.model
    }

    private var state: MenuState {
        MenuState(app: app, windowKey: windowActive == true)
    }

    var body: some Commands {
        FileCommands(host: host)
        CommandGroup(after: .textEditing) {
            Button("Find") { find() }
                .contextCommand(KeyboardShortcut("f"), enabled: state.findCommand)
        }
        ViewCommands(host: host)
        TimerCommands(host: host)
        EntryCommands(host: host)
        ProjectCommands(host: host)
    }

    /// ⌘F: the Timer list's filter, or the Projects or Reports search field.
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
