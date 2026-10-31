// MenuState: which window, tab, and section the main menu's commands act on
// (spec_timer_window.md §9, spec_planner_projects.md §1.2, spec_ios.md §10.3).

import SwiftUI
import TimeTrackingCore

/// The context of the main menu, on the Mac and the iPad. The Timer window
/// (iPad: Timer tab) and the Planner (iPad: a Planner tab) share File, Edit,
/// View, Timer, and Window; the section menu (Project, Calendar, Report, or
/// Activity) exists only while the Planner is in front. An item of one
/// window or section is enabled only there and holds its key equivalent
/// only while enabled, because AppKit sends a key equivalent to the first
/// item that has it even when that item is disabled.
struct MenuState: Equatable {
    /// The Mac's Timer window is key, or the iPad shows the Timer tab.
    var timerKey = false
    /// The Mac's Planner window is key, or the iPad shows a Planner tab.
    var plannerKey = false
    var section: PlannerSection = .projects
    /// A popover, editor, or sheet of the Calendar takes the plain keys.
    var calendarEditing = false

    /// The section menu's title while the Planner is in front.
    var sectionMenuTitle: String {
        section.menuTitle
    }

    var calendarCommands: Bool {
        plannerKey && section == .calendar
    }

    /// Whether a Calendar command's menu item is enabled (plain keys only
    /// while nothing takes text input).
    func isEnabled(_ command: CalendarKeyCommand) -> Bool {
        calendarCommands && (command.shortcut.modifiers.contains(.command) || !calendarEditing)
    }

    var reportCommands: Bool {
        plannerKey && section == .reports
    }

    var activityCommands: Bool {
        plannerKey && section == .activity
    }

    var projectCommands: Bool {
        plannerKey && section == .projects
    }

    var clientsAndAreasCommands: Bool {
        plannerKey && section == .clientsAndAreas
    }

    /// View › Go to Today, Previous Period, Next Period, and Date Range…:
    /// the sections that show a date range.
    var periodCommands: Bool {
        calendarCommands || reportCommands || activityCommands
    }

    /// Edit › Find: the Timer list's filter, the Projects and Reports search.
    var findCommand: Bool {
        timerKey || projectCommands || reportCommands
    }
}

extension MenuState {
    init(router: PlannerRouter?, timerKey: Bool, plannerKey: Bool) {
        self.init(
            timerKey: timerKey,
            plannerKey: plannerKey,
            section: router?.section ?? .projects,
            calendarEditing: router?.calendar.takesTextInput ?? false
        )
    }
}
