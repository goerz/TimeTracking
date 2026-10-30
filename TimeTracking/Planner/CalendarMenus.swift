// CalendarMenus: the Calendar's View and Entry menu items and Activity's
// View submenu (spec_planner_calendar.md §6, spec_planner_activity.md §2).

import SwiftUI
import TimeTrackingCore

/// The Calendar's view commands in the View menu.
struct CalendarViewMenu: View {
    var model: CalendarModel
    var state: PlannerMenuState

    var body: some View {
        Menu("Calendar") {
            ForEach(CalendarKeyCommand.allCases.filter(\.isViewCommand)) { command in
                CalendarCommandButton(model: model, command: command, enabled: state.isEnabled(command))
            }
        }
    }
}

/// The Calendar's entry commands in the Entry menu.
struct CalendarEntryItems: View {
    var model: CalendarModel
    var state: PlannerMenuState

    var body: some View {
        ForEach(CalendarKeyCommand.allCases.filter { !$0.isViewCommand }) { command in
            CalendarCommandButton(model: model, command: command, enabled: state.isEnabled(command))
        }
    }
}

private struct CalendarCommandButton: View {
    var model: CalendarModel
    var command: CalendarKeyCommand
    var enabled: Bool

    var body: some View {
        Button(title) { Task { await model.perform(command) } }
            .keyboardShortcut(command.shortcut)
            .disabled(!enabled)
    }

    private var title: String {
        switch command {
        case .toggleActivity: model.showsActivity ? "Hide Activity Column" : "Show Activity Column"
        case .toggleCalendar: model.showsCalendar ? "Hide Calendar Column" : "Show Calendar Column"
        default: command.title
        }
    }
}

/// View › Activity (spec_planner_activity.md §2).
struct ActivityMenu: View {
    var model: ActivityModel

    var body: some View {
        Menu("Activity") {
            Button("Previous Period") { Task { await model.shiftPeriod(by: -1) } }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Next Period") { Task { await model.shiftPeriod(by: 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Go to Today") {
                model.range.goToToday()
                Task { await model.reload() }
            }
            .keyboardShortcut("t")
            Button("Leave Details or Clear Filter") { Task { await model.escape() } }
            Divider()
            Button("Exclude from Tracking…") {
                if let context = model.contexts.first {
                    model.exclude(context: context)
                } else if let site = model.drill?.subject {
                    model.exclude(site: site)
                }
            }
            .disabled(model.contexts.count != 1 && model.drill == nil)
        }
    }
}
