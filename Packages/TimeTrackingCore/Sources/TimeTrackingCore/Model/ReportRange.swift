// ReportRange: the date range shared by Reports and Activity, with its
// presets, period arrows, and "Go to Today" (reports.md §2).

import Foundation

/// The presets of the date popover, in list order.
public enum RangePreset: String, Codable, Sendable, CaseIterable {
    case today
    case yesterday
    case thisWeek = "this_week"
    case lastWeek = "last_week"
    case thisMonth = "this_month"
    case lastMonth = "last_month"
    case thisYear = "this_year"
    case lastYear = "last_year"
    case weekToDate = "week_to_date"
    case monthToDate = "month_to_date"
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"
    case allTime = "all_time"

    /// The preset's name in the list and the button label.
    public var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .weekToDate: "Week to date"
        case .monthToDate: "Month to date"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }
}

/// The unit the period arrows shift a range by.
public enum RangeUnit: Hashable, Codable, Sendable {
    case day
    case week
    case month
    case year
    /// Any other number of days.
    case days(Int)

    /// The unit a range of these days has by its shape: one day, a Monday-to-
    /// Sunday week, a calendar month, a calendar year, or n days.
    public init(of days: ClosedRange<TrackingDay>) {
        let first = days.lowerBound
        let last = days.upperBound
        let count = first.distance(to: last) + 1
        if count == 1 {
            self = .day
        } else if count == 7, first.isoWeekday == 1 {
            self = .week
        } else if first.day == 1, first.month == 1, last.month == 12, last.day == 31, first.year == last.year {
            self = .year
        } else if first.day == 1, last.adding(days: 1).day == 1, first.year == last.year, first.month == last.month {
            self = .month
        } else {
            self = .days(count)
        }
    }
}

/// A preset (resolved against today, so a stored "This week" is always the
/// current week) or fixed days with the unit their arrows shift by.
public enum ReportRange: Hashable, Codable, Sendable {
    case preset(RangePreset)
    case custom(first: TrackingDay, last: TrackingDay, unit: RangeUnit)

    /// The default: This week.
    public static let standard = Self.preset(.thisWeek)

    /// Fixed days; the unit follows their shape. The days are swapped if
    /// `last` is earlier.
    public static func days(_ first: TrackingDay, _ last: TrackingDay) -> Self {
        let range = min(first, last) ... max(first, last)
        return .custom(first: range.lowerBound, last: range.upperBound, unit: RangeUnit(of: range))
    }

    /// The inclusive days. All time starts at `earliest` (today when `nil`).
    public func days(today: TrackingDay, earliest: TrackingDay?) -> ClosedRange<TrackingDay> {
        switch self {
        case let .custom(first, last, _):
            first ... max(first, last)
        case let .preset(preset):
            Self.days(of: preset, today: today, earliest: earliest)
        }
    }

    /// The unit the arrows shift by; `nil` for All time.
    public var unit: RangeUnit? {
        switch self {
        case let .custom(_, _, unit):
            unit
        case let .preset(preset):
            switch preset {
            case .today, .yesterday: .day
            case .thisWeek, .lastWeek, .weekToDate: .week
            case .thisMonth, .lastMonth, .monthToDate: .month
            case .thisYear, .lastYear: .year
            case .last7Days: .days(7)
            case .last30Days: .days(30)
            case .allTime: nil
            }
        }
    }

    /// Whether the period arrows apply (not for All time).
    public var canShift: Bool {
        unit != nil
    }

    /// The range one period earlier (`by: -1`) or later (`by: 1`); `nil` for
    /// All time. Week and Month to date shift to full weeks and months.
    public func shifted(by step: Int, today: TrackingDay) -> Self? {
        guard let unit else {
            return nil
        }
        let current = days(today: today, earliest: nil)
        let first = current.lowerBound
        switch unit {
        case .day:
            let day = first.adding(days: step)
            return .custom(first: day, last: day, unit: .day)
        case .week:
            let monday = first.adding(days: 1 - first.isoWeekday + 7 * step)
            return .custom(first: monday, last: monday.adding(days: 6), unit: .week)
        case .month:
            let start = first.addingMonths(step)
            return .custom(first: start, last: start.addingMonths(1).adding(days: -1), unit: .month)
        case .year:
            let start = TrackingDay(year: first.year + step, month: 1, day: 1)
            return .custom(first: start, last: TrackingDay(year: start.year, month: 12, day: 31), unit: .year)
        case let .days(count):
            let start = first.adding(days: count * step)
            return .custom(first: start, last: start.adding(days: count - 1), unit: .days(count))
        }
    }

    /// "Go to Today": the current kind applied to today (a week becomes This
    /// week, a month This month, a year This year, a day Today, n days the
    /// n days ending today). All time stays.
    public func goingToToday(today: TrackingDay) -> Self {
        switch unit {
        case .day: .preset(.today)
        case .week: .preset(.thisWeek)
        case .month: .preset(.thisMonth)
        case .year: .preset(.thisYear)
        case let .days(count): .custom(first: today.adding(days: 1 - count), last: today, unit: .days(count))
        case nil: self
        }
    }

    /// The presets whose days equal this range's (the popover highlights them).
    public func matchingPresets(today: TrackingDay, earliest: TrackingDay?) -> [RangePreset] {
        let current = days(today: today, earliest: earliest)
        return RangePreset.allCases.filter { Self.days(of: $0, today: today, earliest: earliest) == current }
    }

    /// The range clipped to its last `maximum` days (Activity's 366-day cap),
    /// and whether it was clipped.
    public func capped(to maximum: Int, today: TrackingDay, earliest: TrackingDay?) -> (days: ClosedRange<TrackingDay>, clipped: Bool) {
        let range = days(today: today, earliest: earliest)
        guard range.lowerBound.distance(to: range.upperBound) + 1 > maximum else {
            return (range, false)
        }
        return (range.upperBound.adding(days: 1 - maximum) ... range.upperBound, true)
    }

    /// A preset's days; calendar periods come from `DayRange` (the tool's
    /// `today`, `week`, `month`, `year` words).
    static func days(of preset: RangePreset, today: TrackingDay, earliest: TrackingDay?) -> ClosedRange<TrackingDay> {
        if let (granularity, day) = calendarPeriod(of: preset, today: today) {
            return DayRange(TrackingPeriod(granularity, containing: day)).days ?? day ... day
        }
        switch preset {
        case .weekToDate: return today.adding(days: 1 - today.isoWeekday) ... today
        case .monthToDate: return TrackingDay(year: today.year, month: today.month, day: 1) ... today
        case .last7Days: return today.adding(days: -6) ... today
        case .last30Days: return today.adding(days: -29) ... today
        case .allTime: return min(earliest ?? today, today) ... today
        default: return today ... today
        }
    }

    /// The calendar period a preset names, with a day inside it.
    private static func calendarPeriod(of preset: RangePreset, today: TrackingDay) -> (Granularity, TrackingDay)? {
        switch preset {
        case .today: (.day, today)
        case .yesterday: (.day, today.adding(days: -1))
        case .thisWeek: (.week, today)
        case .lastWeek: (.week, today.adding(days: -7))
        case .thisMonth: (.month, today)
        case .lastMonth: (.month, today.addingMonths(-1))
        case .thisYear: (.year, today)
        case .lastYear: (.year, TrackingDay(year: today.year - 1, month: 1, day: 1))
        default: nil
        }
    }
}
