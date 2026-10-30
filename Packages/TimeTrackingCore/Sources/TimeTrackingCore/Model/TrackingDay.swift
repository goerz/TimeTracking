// TrackingDay: a calendar date without a zone (spec_data_and_sync.md §8).

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
        let calendar = Self.gregorian
        let date = calendar.date(from: components) ?? .distantPast
        let moved = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        return Self(year: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }

    /// Days from `self` to `other` (positive when `other` is later).
    public func distance(to other: Self) -> Int {
        let calendar = Self.gregorian
        let from = calendar.date(from: components) ?? .distantPast
        let to = calendar.date(from: other.components) ?? .distantPast
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// ISO weekday, 1 (Monday) to 7 (Sunday).
    public var isoWeekday: Int {
        let weekday = Self.gregorian.component(.weekday, from: Self.gregorian.date(from: components) ?? .distantPast)
        return (weekday + 5) % 7 + 1
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: 12)
    }

    /// A Gregorian calendar in UTC for pure date arithmetic.
    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
