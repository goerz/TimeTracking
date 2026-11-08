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
    /// the start of day.
    func axisHour(clock hour: Int) -> Double {
        Double((hour - calendar.startOfDayHour + 24) % 24)
    }

    func axis(_ day: TrackingDay) -> CalendarDayAxis {
        CalendarDayAxis(day: day, calendar: calendar, pointsPerHour: pointsPerHour)
    }

    /// The blocks in the column of `day`: those of the day, and one from the
    /// day before that runs past the start of the day into it.
    func blocks(on day: TrackingDay) -> [ActivityBlock] {
        Self.blocks(blocks, on: day, calendar: calendar)
    }

    /// The background blocks in the column of `day`, likewise.
    func backgroundBlocks(on day: TrackingDay) -> [ActivityBlock] {
        Self.blocks(backgroundBlocks, on: day, calendar: calendar)
    }

    /// The blocks of `day`, and those of other days that reach into its column.
    private static func blocks(_ blocks: [ActivityBlock], on day: TrackingDay, calendar: TrackingCalendar) -> [ActivityBlock] {
        let span = calendar.interval(of: day)
        return blocks.filter { block in
            block.shownDay(startOfDayHour: calendar.startOfDayHour) == day || (block.start < span.end && block.end > span.start)
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
