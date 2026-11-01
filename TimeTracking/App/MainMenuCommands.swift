// MainMenuCommands: the Mac app's main menu (spec_timer.md §9).
// File, Edit, View, Timer, Entry, Project, Window: a fixed set, as
// in Music or Mail; Entry and Project act on what is selected in the view
// shown, and are enabled by that selection.

import SwiftUI
import TimeTrackingCore

/// Every command of the main menu.
struct MainMenuCommands: Commands {
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
        FileCommands(host: host)
        CommandGroup(after: .textEditing) {
            Button("Find") { find() }
                .contextCommand(KeyboardShortcut("f"), enabled: state.findCommand)
        }
        ViewCommands(host: host)
        TimerCommands(host: host)
        EntryCommands(host: host)
        ProjectCommands(host: host)
        CommandGroup(before: .windowList) {
            miniTimerButton
            Divider()
        }
    }

    /// Window › Mini Timer, with the recorded show/hide shortcut (⌥⌘R), as
    /// Music's Window › MiniPlayer.
    @ViewBuilder private var miniTimerButton: some View {
        let button = Button("Mini Timer") { app?.router?.showTimer(focusTask: false) }
        if let key = app?.showHideKey, let character = key.key.first {
            button.keyboardShortcut(KeyEquivalent(character), modifiers: key.eventModifiers)
        } else {
            button
        }
    }

    /// ⌘F: the Timer list's filter, or the Projects or Reports search field.
    private func find() {
        guard let app else {
            return
        }
        if state.timerKey {
            app.activeTimer.list.showFilter()
        } else if state.reportCommands {
            app.sections.reports.focusSearch()
        } else if state.projectCommands {
            app.sections.projects.focusSearch()
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
