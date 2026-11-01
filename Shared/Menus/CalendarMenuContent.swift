// CalendarMenuContent: the Calendar menu's items, on the Mac and the iPad
// (spec_calendar.md §6).

import SwiftUI
import TimeTrackingCore

/// The Calendar's commands: on the selection, then its view. Go to Today,
/// Previous and Next Period, and Go to Date… are the View menu's; the
/// navigation keys (arrows, Tab, Escape) are `CalendarKeyHandlers`.
struct CalendarMenuContent: View {
    var model: CalendarModel
    var state: MenuState

    var body: some View {
        items([.edit, .createEntry, .duplicate, .delete])
        Divider()
        items([.moveEarlier, .moveLater, .lengthen, .shorten])
        Divider()
        items([.fillDay])
        Divider()
        items([.zoomIn, .zoomOut, .zoomReset])
        items([.fewerDays, .moreDays])
        Divider()
        items([.toggleActivity, .toggleCalendar])
    }

    private func items(_ commands: [CalendarKeyCommand]) -> some View {
        ForEach(commands) { command in
            CalendarCommandButton(model: model, command: command, enabled: state.isEnabled(command))
        }
    }
}

/// One Calendar key command; the key works only while the item is enabled.
struct CalendarCommandButton: View {
    var model: CalendarModel
    var command: CalendarKeyCommand
    var enabled: Bool

    var body: some View {
        Button(title) { Task { await model.perform(command) } }
            .contextCommand(command.shortcut, enabled: enabled)
    }

    private var title: String {
        switch command {
        case .toggleActivity: model.showsActivity ? "Hide Activity Column" : "Show Activity Column"
        case .toggleCalendar: model.showsCalendar ? "Hide Calendar Column" : "Show Calendar Column"
        default: command.title
        }
    }
}
