// TrackingDay: a calendar date without a zone (data_and_sync.md §8).

import Foundation

/// A date, `YYYY-MM-DD`. Days start at midnight, local time; an entry's day
/// is the date of its start in its own zone.
public struct TrackingDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1 ... 12).contains(month), (1 ... 31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
        guard adding(days: 0) == self else {
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = Self(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(string)")
        }
        self = day
    }

    /// `YYYY-MM-DD`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The day `days` later (earlier for negative values).
    public func adding(days: Int) -> Self {
        Self(dayNumber: dayNumber + days)
    }

    /// Days from `self` to `other` (positive when `other` is later).
    public func distance(to other: Self) -> Int {
        other.dayNumber - dayNumber
    }

    /// ISO weekday, 1 (Monday) to 7 (Sunday).
    public var isoWeekday: Int {
        // Day 0 (1970-01-01) was a Thursday.
        (dayNumber % 7 + 7 + 3) % 7 + 1
    }

    /// Saturday or Sunday (the Calendar shades them, calendar.md §1.2).
    public var isWeekend: Bool {
        isoWeekday >= 6
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's
    /// `days_from_civil`); invalid days roll over like `Calendar` does.
    var dayNumber: Int {
        let normalizedMonth = month - 1
        let year = year + (normalizedMonth >= 0 ? normalizedMonth / 12 : (normalizedMonth - 11) / 12)
        let month = normalizedMonth - (year - self.year) * 12 + 1
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The day `dayNumber` days after 1970-01-01 (`civil_from_days`).
    init(dayNumber: Int) {
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: 12)
    }
}
