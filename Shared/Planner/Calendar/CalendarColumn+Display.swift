// The Calendar columns' glyphs and titles (spec_planner_calendar.md §1.4).

import TimeTrackingCore

extension CalendarColumn {
    var glyph: String {
        switch self {
        case .activity: "desktopcomputer"
        case .tracked: "stopwatch"
        case .calendar: "calendar"
        }
    }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}
