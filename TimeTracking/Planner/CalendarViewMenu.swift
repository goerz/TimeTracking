// CalendarViewMenu: the View menu's Calendar and Activity submenus and the
// Calendar's key commands as menu items (spec_planner_calendar.md §6,
// spec_planner_activity.md §2).

import SwiftUI
import TimeTrackingCore

/// View › Calendar: the Calendar's view commands; Today is View › Go to Today.
struct CalendarViewMenu: View {
    var model: CalendarModel
    var state: MenuState

    var body: some View {
        Menu("Calendar") {
            items([.zoomIn, .zoomOut, .zoomReset])
            Divider()
            items([.fewerDays, .moreDays])
            Divider()
            items([.previousDay, .nextDay, .previousSpan, .nextSpan])
            Divider()
            items([.toggleActivity, .toggleCalendar])
        }
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

/// View › Activity (spec_planner_activity.md §2); its range commands are
/// View › Go to Today, Previous Period, Next Period, and Date Range….
struct ActivityMenu: View {
    var model: ActivityModel
    var enabled: Bool

    var body: some View {
        Menu("Activity") {
            // Escape's two steps, titled by the one it takes now.
            Button(model.drill == nil ? "Clear Filter" : "Back") { Task { await model.escape() } }
                .disabled(!enabled || (model.drill == nil && model.contexts.isEmpty))
            Divider()
            Button("Exclude from Tracking…") {
                if let context = model.contexts.first {
                    model.exclude(context: context)
                } else if let site = model.drill?.subject {
                    model.exclude(site: site)
                }
            }
            .disabled(!enabled || (model.contexts.count != 1 && model.drill == nil))
        }
    }
}
