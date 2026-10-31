// The date range's labels: the subtitle and the range menu's title
// (spec_planner_reports.md §2.2, §2.3).

import Foundation

extension ReportRange {
    /// "This week · W44", "Week 43 · Oct 19 – 25", "September 2026",
    /// "Oct 5 – 18, 2026", "All time · since Mar 4, 2019".
    public func label(today: TrackingDay, earliest: TrackingDay?) -> String { // swiftlint:disable:this cyclomatic_complexity
        let range = days(today: today, earliest: earliest)
        let first = range.lowerBound
        switch self {
        case let .preset(preset):
            let detail = switch preset {
            case .today, .yesterday: DayText.weekdayShortDate(first)
            case .thisWeek, .lastWeek, .weekToDate: "W\(first.isoWeek.week)"
            case .thisMonth, .lastMonth, .monthToDate: DayText.monthYear(first)
            case .thisYear, .lastYear: String(first.year)
            case .last7Days, .last30Days: DayText.span(range, withYear: false)
            case .allTime: "since \(DayText.monthDayYear(first))"
            }
            return "\(preset.title) · \(detail)"
        case let .custom(_, _, unit):
            switch unit {
            case .day:
                return DayText.weekdayMonthDayYear(first)
            case .week:
                return "Week \(first.isoWeek.week) · \(DayText.span(range, withYear: false))"
            case .month:
                return DayText.monthYear(first)
            case .year:
                return String(first.year)
            case .days:
                return DayText.span(range, withYear: true)
            }
        }
    }
}

extension ReportRange {
    /// The range menu's title, naming the selection: the preset's name while
    /// the range equals one ("This month"), else the range by kind
    /// ("Wed 10/28", "Week 43", "August 2026", "2025", "Oct 5 – 18").
    public func menuTitle(today: TrackingDay, earliest: TrackingDay?) -> String {
        if case let .preset(preset) = self {
            return preset.title
        }
        if let preset = matchingPresets(today: today, earliest: earliest).first {
            return preset.title
        }
        let range = days(today: today, earliest: earliest)
        let first = range.lowerBound
        switch unit {
        case .day:
            return DayText.weekdayShortDate(first)
        case .week:
            return "Week \(first.isoWeek.week)"
        case .month:
            return DayText.monthYear(first)
        case .year:
            return String(first.year)
        case .days, nil:
            return DayText.span(range, withYear: false)
        }
    }
}

/// Fixed English date texts of Reports and Activity.
public enum DayText {
    static let monthNames = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
        "December",
    ]
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Oct".
    public static func shortMonth(_ day: TrackingDay) -> String {
        String(monthNames[day.month - 1].prefix(3))
    }

    /// "Thu".
    public static func shortWeekday(_ day: TrackingDay) -> String {
        String(weekdayNames[day.isoWeekday - 1].prefix(3))
    }

    /// "10/29".
    public static func monthSlashDay(_ day: TrackingDay) -> String {
        "\(day.month)/\(day.day)"
    }

    /// "Thu 10/29".
    public static func weekdayShortDate(_ day: TrackingDay) -> String {
        "\(shortWeekday(day)) \(monthSlashDay(day))"
    }

    /// "October 2026".
    public static func monthYear(_ day: TrackingDay) -> String {
        "\(monthNames[day.month - 1]) \(day.year)"
    }

    /// "Mar 4, 2019".
    public static func monthDayYear(_ day: TrackingDay) -> String {
        "\(shortMonth(day)) \(day.day), \(day.year)"
    }

    /// "Wed, Oct 28, 2026".
    public static func weekdayMonthDayYear(_ day: TrackingDay) -> String {
        "\(shortWeekday(day)), \(monthDayYear(day))"
    }

    /// "Monday, October 26".
    public static func longWeekdayDate(_ day: TrackingDay) -> String {
        "\(weekdayNames[day.isoWeekday - 1]), \(monthNames[day.month - 1]) \(day.day)"
    }

    /// "Oct 23 – 29", "Sep 30 – Oct 29", with the year "Oct 5 – 18, 2026";
    /// across years always "Dec 28, 2025 – Jan 3, 2026".
    public static func span(_ range: ClosedRange<TrackingDay>, withYear: Bool) -> String {
        let first = range.lowerBound
        let last = range.upperBound
        if first.year != last.year {
            return "\(monthDayYear(first)) – \(monthDayYear(last))"
        }
        let start = "\(shortMonth(first)) \(first.day)"
        let end = first.month == last.month ? "\(last.day)" : "\(shortMonth(last)) \(last.day)"
        let text = first == last ? start : "\(start) – \(end)"
        return withYear ? "\(text), \(first.year)" : text
    }
}

extension TrackingDay {
    /// The ISO 8601 week-numbering year and week.
    public var isoWeek: (year: Int, week: Int) {
        let calendar = TrackingPeriod.iso
        let date = calendar.date(from: components) ?? .distantPast
        return (calendar.component(.yearForWeekOfYear, from: date), calendar.component(.weekOfYear, from: date))
    }
}
