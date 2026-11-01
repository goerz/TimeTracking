// EntryMenuItems: the Entry menu, on the Mac and the iPad
// (spec_timer.md §9).

import SwiftUI
import TimeTrackingCore

/// What the Entry menu does with the Timer's entry; each platform passes its own.
struct TimerEntryActions {
    var setProject: () -> Void
    var edit: () -> Void
    var delete: () -> Void
    /// The Timer list has a row to delete.
    var canDelete: Bool
}

/// Commands on the selected entry, wherever it is selected: the Timer's
/// running entry or list row, the Calendar's selection, or the Reports
/// entry list's row, like Music's Song menu. Edit and Delete are one item
/// each, keyed for the view (⌘E and ⌘⌫; Return and Delete in the Calendar).
struct EntryMenuItems: View {
    var router: SectionRouter
    var state: MenuState
    var timer: TimerEntryActions

    /// The one selected row of the Reports entry list.
    private var reportEntry: EntryID? {
        let reports = router.reports
        guard state.reportCommands, reports.state.card == .entries, reports.listSelection.count == 1 else {
            return nil
        }
        return reports.listSelection.first
    }

    var body: some View {
        editButton
        Button("Set Project…", action: timer.setProject)
            .contextCommand(KeyboardShortcut("j"), enabled: state.timerKey)
        calendarItems([.createEntry, .duplicate])
        Divider()
        calendarItems([.moveEarlier, .moveLater, .lengthen, .shorten])
        Divider()
        calendarItems([.fillDay])
        Divider()
        deleteButton
    }

    @ViewBuilder private var editButton: some View {
        if state.calendarCommands {
            CalendarCommandButton(model: router.calendar, command: .edit, enabled: state.isEnabled(.edit))
        } else {
            Button("Edit Entry…") {
                if state.timerKey {
                    timer.edit()
                } else if let id = reportEntry {
                    router.reports.editing = id
                }
            }
            .contextCommand(KeyboardShortcut("e"), enabled: state.timerKey || reportEntry != nil)
        }
    }

    @ViewBuilder private var deleteButton: some View {
        if state.calendarCommands {
            CalendarCommandButton(model: router.calendar, command: .delete, enabled: state.isEnabled(.delete))
        } else {
            Button("Delete Entry…", action: timer.delete)
                .contextCommand(KeyboardShortcut(.delete, modifiers: .command), enabled: state.timerKey && timer.canDelete)
        }
    }

    private func calendarItems(_ commands: [CalendarKeyCommand]) -> some View {
        ForEach(commands) { command in
            CalendarCommandButton(model: router.calendar, command: command, enabled: state.isEnabled(command))
        }
    }
}
