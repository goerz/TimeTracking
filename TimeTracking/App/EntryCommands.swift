// EntryCommands: the Entry menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// The Entry menu, shared with the iPad (`EntryMenuItems`); the Mac's Timer
/// actions act on the running entry or the Timer list's row.
struct EntryCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive
    @FocusedValue(\.timerWindowActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var state: MenuState {
        MenuState(app: app, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    var body: some Commands {
        CommandMenu("Entry") {
            if let app {
                EntryMenuItems(router: app.planner, state: state, timer: TimerEntryActions(
                    setProject: { app.openChipPicker() },
                    edit: { app.editEntry() },
                    delete: { app.timer.alert = app.list.deleteAlert() },
                    canDelete: app.list.selection != nil && app.presentation.listFocused
                ))
            }
        }
    }
}
