// TrackingCalendar: days, weeks, and pieces in a zone (spec_data_and_sync.md §1.5, §8).

public import Foundation

/// Day arithmetic in one time zone. Midnight is `Calendar.startOfDay`, so a
/// day whose midnight does not exist (a DST change at 00:00) starts at the
/// first instant that does.
///
/// With a `midnightHour` other than 0 the days are the ones the app shows
/// (§8): each starts at that hour. A day that starts in the morning is named
/// after the date it starts on, one that starts at noon or later after the
/// date it ends on, so a day keeps the name of the date most of it lies on.
/// Storage always uses `midnightHour` 0.
public struct TrackingCalendar: Sendable {
    public let timeZone: TimeZone
    /// The hour of the local clock at which a day starts, 0 to 23.
    public let midnightHour: Int
    private let calendar: Calendar

    public init(timeZone: TimeZone, midnightHour: Int = 0) {
        self.timeZone = timeZone
        self.midnightHour = SyncedSettingKey<Int>.midnightHour.clamped(midnightHour)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The calendar of an IANA identifier, or of the current zone when the
    /// identifier is unknown.
    public init(timeZoneIdentifier: String, midnightHour: Int = 0) {
        self.init(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current, midnightHour: midnightHour)
    }

    /// The day of `date`: its local date, shifted by `midnightHour`.
    public func day(containing date: Date) -> TrackingDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let local = TrackingDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
        guard midnightHour != 0 else {
            return local
        }
        return dayChange(on: local).days[date < dayChange(on: local).instant ? 0 : 1]
    }

    /// The first instant of `day`.
    public func startOfDay(_ day: TrackingDay) -> Date {
        guard midnightHour != 0 else {
            return localMidnight(day)
        }
        return dayChange(on: midnightHour < 12 ? day : day.adding(days: -1)).instant
    }

    /// The instant the local date `date` changes from one day to the next,
    /// and those two days. Each local date holds exactly one change. An hour
    /// a DST change skips is replaced by the first instant after it, and of
    /// an hour it repeats the first one counts.
    func dayChange(on date: TrackingDay) -> (instant: Date, days: [TrackingDay]) {
        let midnight = localMidnight(date)
        let instant = calendar.date(bySettingHour: midnightHour, minute: 0, second: 0, of: midnight) ?? midnight
        let earlier = midnightHour < 12 ? date.adding(days: -1) : date
        return (instant, [earlier, earlier.adding(days: 1)])
    }

    private func localMidnight(_ day: TrackingDay) -> Date {
        var parts = day.components
        parts.hour = 12
        let noon = calendar.date(from: parts) ?? .distantPast
        return calendar.startOfDay(for: noon)
    }

    /// From the day's start to the next day's start: 23 or 25 hours on DST days.
    public func interval(of day: TrackingDay) -> DateInterval {
        DateInterval(start: startOfDay(day), end: startOfDay(day.adding(days: 1)))
    }

    /// The interval from the start of `range.lowerBound` to the end of
    /// `range.upperBound`.
    public func interval(of range: ClosedRange<TrackingDay>) -> DateInterval {
        DateInterval(start: startOfDay(range.lowerBound), end: startOfDay(range.upperBound.adding(days: 1)))
    }

    /// The Monday-to-Sunday week of `day`.
    public func week(containing day: TrackingDay) -> [TrackingDay] {
        let monday = day.adding(days: 1 - day.isoWeekday)
        return (0 ..< 7).map { monday.adding(days: $0) }
    }

    /// The periods of `granularity` that meet `range`, in order; `total` is
    /// one period.
    public func periods(_ granularity: Granularity, covering range: ClosedRange<TrackingDay>) -> [TrackingPeriod] {
        if granularity == .total {
            return [TrackingPeriod(.total, containing: range.lowerBound, rangeStart: range.lowerBound)]
        }
        var periods: [TrackingPeriod] = []
        var period = TrackingPeriod(granularity, containing: range.lowerBound)
        while period.start <= range.upperBound {
            periods.append(period)
            guard let next = period.nextStart else {
                break
            }
            period = TrackingPeriod(granularity: granularity, start: next)
        }
        return periods
    }

    /// The day of an entry: the date of its start in its own zone.
    public static func day(of entry: TimeEntry) -> TrackingDay {
        Self(timeZoneIdentifier: entry.timeZone).day(containing: entry.start)
    }

    /// The day an entry is shown on: the day of its start in its own zone.
    public func displayDay(of entry: TimeEntry) -> TrackingDay {
        zoned(for: entry).day(containing: entry.start)
    }

    /// `entry` as the app shows it: one piece per day it lies on in its own
    /// zone, each with its part of the interval and that day as `day`, and
    /// only the last one running. Stored entries never change; every piece
    /// has the entry's id.
    public func pieces(of entry: TimeEntry, at now: Date) -> [TimeEntry] {
        let calendar = zoned(for: entry)
        var piece = entry
        piece.day = calendar.day(containing: entry.start)
        var pieces: [TimeEntry] = []
        let end = entry.end ?? now
        var next = calendar.startOfDay(piece.day.adding(days: 1))
        while next < end {
            var earlier = piece
            earlier.end = next
            pieces.append(earlier)
            piece.start = next
            piece.day = piece.day.adding(days: 1)
            next = calendar.startOfDay(piece.day.adding(days: 1))
        }
        return pieces + [piece]
    }

    private func zoned(for entry: TimeEntry) -> Self {
        entry.timeZone == timeZone.identifier ? self : Self(timeZoneIdentifier: entry.timeZone, midnightHour: midnightHour)
    }

    /// The instants `days` can cover in any zone, for finding the entries
    /// with a piece on them by interval overlap: each entry's pieces follow
    /// its own zone, and no zone's offset from GMT exceeds 16 hours.
    public func reach(of days: ClosedRange<TrackingDay>) -> DateInterval {
        let interval = Self(timeZone: .gmt, midnightHour: midnightHour).interval(of: days)
        return DateInterval(start: interval.start - 16 * 3600, end: interval.end + 16 * 3600)
    }
}
