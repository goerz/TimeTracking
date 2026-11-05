// CalendarCommandButton: one Calendar key command as a menu item, in the
// Entry and View menus (calendar.md §5).

import SwiftUI
import TimeTrackingCore

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
