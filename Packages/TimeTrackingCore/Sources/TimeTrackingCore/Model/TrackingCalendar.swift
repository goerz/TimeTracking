// TrackingCalendar: days, weeks, midnights in a zone (spec_data_and_sync.md §1.5, §8).

public import Foundation

/// Day arithmetic in one time zone. Midnight is `Calendar.startOfDay`, so a
/// day whose midnight does not exist (a DST change at 00:00) starts at the
/// first instant that does.
public struct TrackingCalendar: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The calendar of an IANA identifier, or of the current zone when the
    /// identifier is unknown.
    public init(timeZoneIdentifier: String) {
        self.init(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current)
    }

    /// The local date of `date`.
    public func day(containing date: Date) -> TrackingDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return TrackingDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The first instant of `day`.
    public func startOfDay(_ day: TrackingDay) -> Date {
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

    /// The midnights strictly between `after` and `before` in `zone`.
    public static func midnights(after start: Date, before end: Date, in zone: TimeZone) -> [Date] {
        let calendar = Self(timeZone: zone)
        var result: [Date] = []
        var day = calendar.day(containing: start).adding(days: 1)
        var midnight = calendar.startOfDay(day)
        while midnight < end {
            if midnight > start {
                result.append(midnight)
            }
            day = day.adding(days: 1)
            midnight = calendar.startOfDay(day)
        }
        return result
    }
}
