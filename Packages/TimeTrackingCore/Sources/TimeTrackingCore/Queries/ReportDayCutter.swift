// ReportDayCutter: the parts of stored entries on the days the app shows
// (data_and_sync.md §8).

import Foundation
import GRDB

/// Cuts entry rows at every day change they cross. Reports scan many entries
/// over few dates, so each date's start is worked out once per zone.
struct ReportDayCutter {
    let midnightHour: Int
    let now: Int64
    private var zones: [String: ZoneDays] = [:]

    init(midnightHour: Int, now: Int64) {
        self.midnightHour = midnightHour
        self.now = now
    }

    /// The parts of a `time_entry` row with `day`, `time_zone`, `start`, and
    /// `end`, in order; an entry without length lies on the day of its start.
    mutating func parts(of row: Row) -> [(day: TrackingDay, seconds: Int)] {
        let name: String = row["time_zone"]
        let hour = midnightHour
        return zones[name, default: ZoneDays(TrackingCalendar(timeZoneIdentifier: name, midnightHour: hour))].parts(
            date: row["day"],
            start: row["start"],
            end: (row["end"] as Int64?) ?? now
        )
    }
}

/// The days of one zone, with what is known of them so far.
private struct ZoneDays {
    let calendar: TrackingCalendar
    private var dates: [String: TrackingDay] = [:]
    private var starts: [TrackingDay: Int64] = [:]

    init(_ calendar: TrackingCalendar) {
        self.calendar = calendar
    }

    mutating func parts(date: String, start: Int64, end: Int64) -> [(day: TrackingDay, seconds: Int)] {
        var day = shownDay(of: start, onDate: date)
        var next = self.start(of: day.adding(days: 1))
        guard next < end else {
            return [(day, Int(max(0, end - start)))]
        }
        var parts = [(day: day, seconds: Int(next - start))]
        while true {
            day = day.adding(days: 1)
            let later = self.start(of: day.adding(days: 1))
            guard later < end else {
                parts.append((day, Int(end - next)))
                return parts
            }
            parts.append((day, Int(later - next)))
            next = later
        }
    }

    /// The shown day of an instant on the local `date`: that date, or the
    /// one next to it when the day change lies between them.
    private mutating func shownDay(of instant: Int64, onDate date: String) -> TrackingDay {
        let day = dates[date] ?? TrackingDay(date) ?? TrackingDay(year: 1970, month: 1, day: 1)
        dates[date] = day
        if instant < start(of: day) {
            return day.adding(days: -1)
        }
        return instant < start(of: day.adding(days: 1)) ? day : day.adding(days: 1)
    }

    private mutating func start(of day: TrackingDay) -> Int64 {
        if let known = starts[day] {
            return known
        }
        let start = Time.seconds(calendar.startOfDay(day))
        starts[day] = start
        return start
    }
}
