// The Calendar columns' glyphs and titles (spec_calendar.md §1.4).

import TimeTrackingCore

extension CalendarColumn {
    var glyph: String {
        switch self {
        case .activity: SymbolName.mac
        case .tracked: SymbolName.timer
        case .calendar: SymbolName.calendar
        }
    }

    var title: String {
        switch self {
        case .activity: "Activity"
        case .tracked: "Tracked"
        case .calendar: "Calendar"
        }
    }
}
