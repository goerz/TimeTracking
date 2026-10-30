// Granularity and TrackingPeriod: report buckets (spec_data_and_sync.md §7.3, §8).

import Foundation

/// The bucket size of a report.
public enum Granularity: String, Codable, Sendable, CaseIterable {
    case day
    case week
    case month
    case year
    case total
}

/// One bucket of a report: a day, an ISO week (Monday first), a month, a
/// year, or the whole range.
public struct TrackingPeriod: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var granularity: Granularity
    /// The first day of the period; for `total`, the range's first day.
    public var start: TrackingDay

    public init(granularity: Granularity, start: TrackingDay) {
        self.granularity = granularity
        self.start = start
    }

    /// The period of `granularity` containing `day`; `total` periods start
    /// at `rangeStart`.
    public init(_ granularity: Granularity, containing day: TrackingDay, rangeStart: TrackingDay? = nil) {
        self.granularity = granularity
        switch granularity {
        case .day:
            self.start = day
        case .week:
            self.start = day.adding(days: 1 - day.isoWeekday)
        case .month:
            self.start = TrackingDay(year: day.year, month: day.month, day: 1)
        case .year:
            self.start = TrackingDay(year: day.year, month: 1, day: 1)
        case .total:
            self.start = rangeStart ?? day
        }
    }

    /// The key used in listings: `2026-10-20`, `2026-W43`, `2026-10`,
    /// `2026`, or `total`.
    public var description: String {
        switch granularity {
        case .day:
            return start.description
        case .week:
            let calendar = Self.iso
            let date = calendar.date(from: start.components) ?? .distantPast
            let week = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        case .month:
            return String(format: "%04d-%02d", start.year, start.month)
        case .year:
            return String(format: "%04d", start.year)
        case .total:
            return "total"
        }
    }

    /// The day after the period's last day; `nil` for `total`.
    public var nextStart: TrackingDay? {
        switch granularity {
        case .day:
            start.adding(days: 1)
        case .week:
            start.adding(days: 7)
        case .month:
            if start.month == 12 {
                TrackingDay(year: start.year + 1, month: 1, day: 1)
            } else {
                TrackingDay(year: start.year, month: start.month + 1, day: 1)
            }
        case .year:
            TrackingDay(year: start.year + 1, month: 1, day: 1)
        case .total:
            nil
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.start < rhs.start
    }

    static let iso: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
