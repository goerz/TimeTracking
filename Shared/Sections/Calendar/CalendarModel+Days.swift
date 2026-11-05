// CalendarModel+Days: today, the visible columns, and each day's axis and
// editing rules (calendar.md §1, §2).

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

    /// The clock's `hour` as hours below a column's top: a column starts at
    /// Midnight.
    func axisHour(clock hour: Int) -> Double {
        Double((hour - calendar.midnightHour + 24) % 24)
    }

    func axis(_ day: TrackingDay) -> CalendarDayAxis {
        CalendarDayAxis(day: day, calendar: calendar, pointsPerHour: pointsPerHour)
    }

    /// The blocks in the column of `day`: those of the day, and with a
    /// Midnight also one from the day before that reaches into it.
    func blocks(on day: TrackingDay) -> [ActivityBlock] {
        let span = calendar.interval(of: day)
        return blocks.filter { block in
            block.shownDay == day.description || (calendar.midnightHour != 0 && block.start < span.end && block.end > span.start)
        }
    }

    /// The background stretches in the column of `day`, likewise.
    func stretches(on day: TrackingDay) -> [ActivityBackgroundStretch] {
        let span = calendar.interval(of: day)
        return stretches.filter { stretch in
            stretch.shownDay == day.description || (calendar.midnightHour != 0 && stretch.start < span.end && stretch.end > span.start)
        }
    }

    /// The all-day events of the date `day` is named after (§1.4).
    func allDayEvents(on day: TrackingDay) -> [CalendarEvent] {
        (externalEvents + timeBlocks.map(\.event)).filter { $0.isAllDay(on: day, in: calendar.timeZone) }
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
