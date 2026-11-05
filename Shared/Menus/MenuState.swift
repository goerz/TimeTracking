// MenuState: which window, tab, and section the main menu's commands act on
// (timer.md §9, projects.md §1.2, ios.md §10.3).

import SwiftUI
import TimeTrackingCore

/// The context of the main menu, on the Mac and the iPad. A Timer view
/// (iPad: the Timer tab) and a section (iPad: a section tab) share File,
/// Edit, View, Timer, and Window; the section menu (Project, Calendar,
/// Report, or Activity) exists only while a section is in front. An item of one
/// window or section is enabled only there and holds its key equivalent
/// only while enabled, because AppKit sends a key equivalent to the first
/// item that has it even when that item is disabled.
struct MenuState: Equatable {
    /// A Timer view is in the Mac's key window, or the iPad shows the Timer tab.
    var timerKey = false
    /// A section is shown in the Mac's key main window, or the iPad shows a
    /// section tab.
    var sectionKey = false
    var section: MainSection = .projects
    /// A popover, editor, or sheet of the Calendar takes the plain keys.
    var calendarEditing = false

    /// The section menu's title while a section is in front.
    var sectionMenuTitle: String {
        section.menuTitle
    }

    var calendarCommands: Bool {
        sectionKey && section == .calendar
    }

    /// Whether a Calendar command's menu item is enabled (plain keys only
    /// while nothing takes text input).
    func isEnabled(_ command: CalendarKeyCommand) -> Bool {
        calendarCommands && (command.shortcut.modifiers.contains(.command) || !calendarEditing)
    }

    var reportCommands: Bool {
        sectionKey && section == .reports
    }

    var activityCommands: Bool {
        sectionKey && section == .activity
    }

    var projectCommands: Bool {
        sectionKey && section == .projects
    }

    /// View › Go to Today, Previous Period, Next Period, and Date Range…:
    /// the sections that show a date range; on the iPad not Projects
    /// (ios.md, IOS-34).
    var periodCommands: Bool {
        #if os(macOS)
            calendarCommands || reportCommands || activityCommands || projectCommands
        #else
            calendarCommands || reportCommands || activityCommands
        #endif
    }

    /// Edit › Find: the Timer list's filter, the Calendar, Projects, and
    /// Reports search.
    var findCommand: Bool {
        timerKey || calendarCommands || projectCommands || reportCommands
    }
}

extension MenuState {
    init(router: SectionRouter?, timerKey: Bool, sectionKey: Bool) {
        self.init(
            timerKey: timerKey,
            sectionKey: sectionKey,
            section: router?.section ?? .projects,
            calendarEditing: router?.calendar.takesTextInput ?? false
        )
    }
}
