// EntryCommands: the main menu's Entry menu, the commands on the selected
// entries of the Timer window and the Planner's Calendar
// (spec_timer_window.md §9, spec_planner_calendar.md §6).

import SwiftUI
import TimeTrackingCore

/// One menu for entries wherever they are selected. Edit and Delete are one
/// item each, acting on the Timer window's entry or the Calendar's selection.
struct EntryCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var app: AppModel? {
        host.model
    }

    private var calendar: CalendarModel? {
        host.model?.planner.calendar
    }

    private var state: MenuState {
        MenuState(host: host, timerKey: timerActive ?? false, plannerKey: plannerActive ?? false)
    }

    var body: some Commands {
        CommandMenu("Entry") {
            Button("Set Project…") { app?.openChipPicker() }
                .contextCommand(KeyboardShortcut("p"), enabled: state.timerKey)
            editButton
            calendarItems([.createEntry, .duplicate, .fillDay])
            Divider()
            calendarItems([.nextEntry, .previousEntry])
            Divider()
            calendarItems([.moveEarlier, .moveLater, .lengthen, .shorten])
            Divider()
            calendarItems([.escape])
            deleteButton
        }
    }

    /// The Timer window's running or selected entry (⌘E), or the editor of
    /// the Calendar's selected entry or time block (Return).
    @ViewBuilder private var editButton: some View {
        if state.calendarCommands, let calendar {
            CalendarCommandButton(model: calendar, command: .edit, enabled: state.isEnabled(.edit))
        } else {
            Button("Edit Entry…") { app?.editEntry() }
                .contextCommand(KeyboardShortcut("e"), enabled: state.timerKey)
        }
    }

    /// The Timer list's selected row, after an alert (⌘⌫), or the Calendar's
    /// selection, undoable (Delete).
    @ViewBuilder private var deleteButton: some View {
        if state.calendarCommands, let calendar {
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
        if let calendar {
            ForEach(commands) { command in
                CalendarCommandButton(model: calendar, command: command, enabled: state.isEnabled(command))
            }
        }
    }
}
