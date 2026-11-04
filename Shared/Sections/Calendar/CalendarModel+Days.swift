// CalendarModel+Days: today, the visible columns, and each day's axis and
// editing rules (spec_calendar.md §1, §2).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    var today: TrackingDay {
        calendar.day(containing: clock.now)
    }

    /// The visible columns of each day.
    var columns: [CalendarColumn] {
        CalendarColumn.allCases.filter { column in
            switch column {
            case .activity: showsActivity
            case .tracked: true
            case .calendar: showsCalendar
            }
        }
    }

    func axis(_ day: TrackingDay) -> CalendarDayAxis {
        CalendarDayAxis(day: day, calendar: calendar, pointsPerHour: pointsPerHour)
    }

    func editing(_ day: TrackingDay, option: Bool = false, limitToNow: Bool = true) -> CalendarEditing {
        CalendarEditing(
            day: calendar.interval(of: day),
            now: clock.now,
            snap: CalendarSnap(minutes: option ? 1 : snapMinutes),
            limitToNow: limitToNow
        )
    }
}
