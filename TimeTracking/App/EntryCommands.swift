// EntryCommands: the Entry menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// Commands on the selected entry, wherever it is selected: the Timer's
/// running entry or list row, the Calendar's selection, or the Reports
/// entry list's row, like Music's Song menu. Edit and Delete are one item
/// each, keyed for the view (⌘E and ⌘⌫; Return and Delete in the Calendar).
struct EntryCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive

    private var app: AppModel? {
        host.model
    }

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(app: app, windowKey: windowActive == true)
    }

    /// The one selected row of the Reports entry list.
    private var reportEntry: EntryID? {
        guard state.reportCommands, let reports = router?.reports, reports.state.card == .entries,
              reports.listSelection.count == 1
        else {
            return nil
        }
        return reports.listSelection.first
    }

    var body: some Commands {
        CommandMenu("Entry") {
            editButton
            Button("Set Project…") { app?.openChipPicker() }
                .contextCommand(KeyboardShortcut("j"), enabled: state.timerKey)
            calendarItems([.createEntry, .duplicate])
            Divider()
            calendarItems([.moveEarlier, .moveLater, .lengthen, .shorten])
            Divider()
            calendarItems([.fillDay])
            Divider()
            deleteButton
        }
    }

    @ViewBuilder private var editButton: some View {
        if state.calendarCommands, let calendar = router?.calendar {
            CalendarCommandButton(model: calendar, command: .edit, enabled: state.isEnabled(.edit))
        } else {
            Button("Edit Entry…") {
                if state.timerKey {
                    app?.editEntry()
                } else if let id = reportEntry {
                    router?.reports.editing = id
                }
            }
            .contextCommand(KeyboardShortcut("e"), enabled: state.timerKey || reportEntry != nil)
        }
    }

    @ViewBuilder private var deleteButton: some View {
        if state.calendarCommands, let calendar = router?.calendar {
            CalendarCommandButton(model: calendar, command: .delete, enabled: state.isEnabled(.delete))
        } else {
            Button("Delete Entry…") {
                if let app {
                    app.timer.alert = app.list.deleteAlert()
                }
            }
            .contextCommand(
                KeyboardShortcut(.delete, modifiers: .command),
                enabled: state.timerKey && app?.list.selection != nil && app?.presentation.listFocused == true
            )
        }
    }

    @ViewBuilder
    private func calendarItems(_ commands: [CalendarKeyCommand]) -> some View {
        if let calendar = router?.calendar {
            ForEach(commands) { command in
                CalendarCommandButton(model: calendar, command: command, enabled: state.isEnabled(command))
            }
        }
    }
}
