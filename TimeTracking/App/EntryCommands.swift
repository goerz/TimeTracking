// EntryCommands: the Entry menu (timer.md §9).

import SwiftUI
import TimeTrackingCore

/// The Entry menu, shared with the iPad (`EntryMenuItems`); the Mac's Timer
/// actions act on the running entry or the Timer list's row.
struct EntryCommands: Commands {
    var host: AppHost
    @FocusedValue(\.mainWindowActive) private var windowActive
    @FocusedValue(\.timerViewActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var state: MenuState {
        MenuState(app: app, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    var body: some Commands {
        CommandMenu("Entry") {
            if let app {
                // The Timer view in the key window.
                let view = app.activeTimer
                EntryMenuItems(router: app.sections, state: state, timer: TimerEntryActions(
                    setProject: { app.openChipPicker(in: view) },
                    edit: { app.editEntry(in: view) },
                    delete: { app.timer.alert = view.list.deleteAlert() },
                    canDelete: view.list.selection != nil && view.listFocused
                ))
            }
        }
    }
}
