// MenuState: which window and section the main menu's commands act on
// (spec_timer_window.md §9, spec_planner_projects.md §1.2).

import SwiftUI
import TimeTrackingCore

/// The context of the main menu. Every menu and item is always listed; an
/// item of one window or section is enabled only there, and holds its key
/// equivalent only while enabled, because AppKit sends a key equivalent to
/// the first item that has it even when that item is disabled.
struct MenuState: Equatable {
    var timerKey = false
    var plannerKey = false
    var section: PlannerSection = .projects
    var showsClientsAndAreas = false
    /// A popover, editor, or sheet of the Calendar takes the plain keys.
    var calendarEditing = false

    /// Planner sections (⌘1 to ⌘4) and Clients & Areas.
    var sectionCommands: Bool {
        plannerKey
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
        plannerKey && section == .projects && !showsClientsAndAreas
    }

    var clientsAndAreasCommands: Bool {
        plannerKey && section == .projects && showsClientsAndAreas
    }

    /// View › Go to Today: the sections that show a date range.
    var todayCommand: Bool {
        calendarCommands || reportCommands || activityCommands
    }

    /// View › Previous Period and Next Period: Reports and Activity.
    var periodCommands: Bool {
        reportCommands || activityCommands
    }

    /// Edit › Find: the Timer list's filter, the Projects and Reports search.
    var findCommand: Bool {
        timerKey || projectCommands || reportCommands
    }
}

extension MenuState {
    init(host: AppHost, timerKey: Bool, plannerKey: Bool) {
        let router = host.model?.planner
        self.init(
            timerKey: timerKey,
            plannerKey: plannerKey,
            section: router?.section ?? .projects,
            showsClientsAndAreas: router?.projects.showsClientsAndAreas ?? false,
            calendarEditing: router?.calendar.takesTextInput ?? false
        )
    }
}
