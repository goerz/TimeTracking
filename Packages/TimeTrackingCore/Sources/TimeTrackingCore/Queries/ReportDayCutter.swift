// ReportDayCutter: the parts of stored entries on the days the app shows
// (spec_data_and_sync.md §8).

import Foundation
import GRDB

/// Cuts entry rows at the day change. A stored entry lies on one local
/// date, which has one day change, so it has at most two parts. Reports scan
/// many entries over few dates, so each date's change is worked out once per
/// zone.
struct ReportDayCutter {
    let midnightHour: Int
    let now: Int64
    private var calendars: [String: TrackingCalendar] = [:]
    private var changes: [String: (instant: Int64, days: [TrackingDay])] = [:]

    init(midnightHour: Int, now: Int64) {
        self.midnightHour = midnightHour
        self.now = now
    }

    /// The parts of a `time_entry` row with `day`, `time_zone`, `start`, and
    /// `end`, in order; an entry without length lies on the side of its start.
    mutating func parts(of row: Row) -> [(day: TrackingDay, seconds: Int)] {
        let change = change(zone: row["time_zone"], date: row["day"])
        let start: Int64 = row["start"]
        let end = (row["end"] as Int64?) ?? now
        var parts: [(TrackingDay, Int)] = []
        if start < change.instant {
            parts.append((change.days[0], Int(max(0, min(end, change.instant) - start))))
        }
        if end > change.instant || start >= change.instant {
            parts.append((change.days[1], Int(max(0, end - max(start, change.instant)))))
        }
        return parts
    }

    private mutating func change(zone: String, date: String) -> (instant: Int64, days: [TrackingDay]) {
        let key = zone + date
        if let known = changes[key] {
            return known
        }
        let calendar = calendars[zone] ?? TrackingCalendar(timeZoneIdentifier: zone, midnightHour: midnightHour)
        calendars[zone] = calendar
        let found = calendar.dayChange(on: TrackingDay(date) ?? TrackingDay(year: 1970, month: 1, day: 1))
        let change = (Time.seconds(found.instant), found.days)
        changes[key] = change
        return change
    }
}
