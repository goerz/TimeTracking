// DateArgument and DayRange: the date and range arguments of the tool
// (spec_automation.md §3.2).

public import Foundation

/// A parsed date argument: an instant (`2026-10-29T09:15`, offset optional)
/// or a period of whole days (`2026-10-29`, `2026-W44`, `2026-10`, `today`,
/// `yesterday`, `week`, `last-week`, `month`, `last-month`, `year`, `-3d`,
/// `-2w`, `-1m`).
public enum DateArgument: Equatable, Sendable {
    case instant(Date)
    /// The days from `from` up to, not including, `to`.
    case period(DayRange)

    /// Parses `text` relative to `now` in `calendar`'s zone.
    public static func parse(_ text: String, now: Date, calendar: TrackingCalendar) throws(AutomationError) -> Self {
        let text = text.trimmed
        let today = calendar.day(containing: now)
        if let period = word(text.lowercased(), today: today) ?? relative(text, today: today) ?? literal(text) {
            return .period(period)
        }
        if text.contains("T"), let date = LaunchArguments.parseInstant(text, timeZone: calendar.timeZone) {
            return .instant(date)
        }
        throw .usage("Malformed date \"\(text)\".")
    }

    /// The first day: the period's, or the instant's date.
    public func firstDay(in calendar: TrackingCalendar) -> TrackingDay {
        switch self {
        case let .instant(date): calendar.day(containing: date)
        case let .period(range): range.from
        }
    }

    /// The days meant by `--day`, `--week`, or `--month`: the period
    /// itself, or for a single day the `granularity` period containing it.
    public func range(_ granularity: Granularity, in calendar: TrackingCalendar) -> DayRange {
        let first = firstDay(in: calendar)
        if case let .period(range) = self, range.dayCount > 1 {
            return range
        }
        return DayRange(TrackingPeriod(granularity, containing: first))
    }

    /// The instant meant by `--at`, `--start`, or `--end`: a period means
    /// the start of its first day.
    public func instant(in calendar: TrackingCalendar) -> Date {
        switch self {
        case let .instant(date): date
        case let .period(range): calendar.startOfDay(range.from)
        }
    }

    private static func word(_ word: String, today: TrackingDay) -> DayRange? {
        switch word {
        case "today": DayRange(TrackingPeriod(.day, containing: today))
        case "yesterday": DayRange(TrackingPeriod(.day, containing: today.adding(days: -1)))
        case "week": DayRange(TrackingPeriod(.week, containing: today))
        case "last-week": DayRange(TrackingPeriod(.week, containing: today.adding(days: -7)))
        case "month": DayRange(TrackingPeriod(.month, containing: today))
        case "last-month": DayRange(TrackingPeriod(.month, containing: today.addingMonths(-1)))
        case "year": DayRange(TrackingPeriod(.year, containing: today))
        default: nil
        }
    }

    private static func relative(_ text: String, today: TrackingDay) -> DayRange? {
        guard let match = text.wholeMatch(of: /-(\d{1,4})([dwm])/), let count = Int(match.1) else {
            return nil
        }
        switch match.2 {
        case "d": return DayRange(TrackingPeriod(.day, containing: today.adding(days: -count)))
        case "w": return DayRange(TrackingPeriod(.week, containing: today.adding(days: -7 * count)))
        default: return DayRange(TrackingPeriod(.month, containing: today.addingMonths(-count)))
        }
    }

    private static func literal(_ text: String) -> DayRange? {
        if let day = TrackingDay(text), day.description == text {
            return DayRange(TrackingPeriod(.day, containing: day))
        }
        if let match = text.wholeMatch(of: /(\d{4})-W(\d{2})/), let year = Int(match.1), let week = Int(match.2) {
            var parts = DateComponents()
            parts.weekOfYear = week
            parts.yearForWeekOfYear = year
            parts.weekday = 2
            guard (1 ... 53).contains(week), let date = TrackingPeriod.iso.date(from: parts) else {
                return nil
            }
            let day = TrackingCalendar(timeZone: TrackingPeriod.iso.timeZone).day(containing: date)
            let period = TrackingPeriod(.week, containing: day)
            return period.description == text ? DayRange(period) : nil
        }
        if let match = text.wholeMatch(of: /(\d{4})-(\d{2})/), let year = Int(match.1), let month = Int(match.2) {
            return (1 ... 12)
                .contains(month) ? DayRange(TrackingPeriod(.month, containing: TrackingDay(year: year, month: month, day: 1))) : nil
        }
        return nil
    }
}

/// A half-open range of days, `from` included, `to` excluded.
public struct DayRange: Hashable, Sendable {
    public var from: TrackingDay
    public var to: TrackingDay

    public init(from: TrackingDay, to: TrackingDay) {
        self.from = from
        self.to = to
    }

    /// The days of a day, week, month, or year period.
    public init(_ period: TrackingPeriod) {
        self.init(from: period.start, to: period.nextStart ?? period.start.adding(days: 1))
    }

    public var dayCount: Int {
        from.distance(to: to)
    }

    /// The days as a closed range; `nil` when the range is empty.
    public var days: ClosedRange<TrackingDay>? {
        to > from ? from ... to.adding(days: -1) : nil
    }

    /// The instants from the start of `from` to the start of `to`.
    public func interval(in calendar: TrackingCalendar) -> DateInterval {
        DateInterval(start: calendar.startOfDay(from), end: max(calendar.startOfDay(from), calendar.startOfDay(to)))
    }

    /// The longest range allowed without `--all-time`.
    public static let maximumDays = 366

    /// The range of the options `--from`/`--to` or `--day`/`--week`/`--month`;
    /// `defaultRange` when none is given, `nil` for all time. A `--from`
    /// without `--to` runs through today.
    public static func resolve( // swiftlint:disable:this function_parameter_count
        from: DateArgument?,
        to: DateArgument?,
        day: DateArgument?,
        week: DateArgument?,
        month: DateArgument?,
        allTime: Bool,
        defaultRange: Self?,
        now: Date,
        calendar: TrackingCalendar
    ) throws(AutomationError) -> Self? {
        let shorthands = [(day, Granularity.day), (week, .week), (month, .month)].compactMap { argument, granularity in
            argument.map { ($0, granularity) }
        }
        if shorthands.count > 1 || (!shorthands.isEmpty && (from != nil || to != nil)) {
            throw .usage("Give either --from/--to or one of --day, --week, --month.")
        }
        var range: Self?
        if let (argument, granularity) = shorthands.first {
            range = argument.range(granularity, in: calendar)
        } else if let from {
            let start = from.firstDay(in: calendar)
            let end = to?.firstDay(in: calendar) ?? max(start, calendar.day(containing: now)).adding(days: 1)
            range = Self(from: start, to: end)
        } else if to != nil {
            throw .usage("--to needs --from.")
        }
        guard let range else {
            return allTime ? nil : defaultRange
        }
        guard range.to > range.from else {
            throw .usage("The range \(range.from) to \(range.to) is empty.")
        }
        if range.dayCount > maximumDays, !allTime {
            throw .usage("The range spans \(range.dayCount) days, more than \(maximumDays); add --all-time.")
        }
        return range
    }
}

extension TrackingDay {
    /// The same day of the month `months` months away, clamped to the month's end.
    func addingMonths(_ months: Int) -> Self {
        let index = year * 12 + (month - 1) + months
        let year = index / 12
        let month = index % 12 + 1
        let first = TrackingDay(year: year, month: month, day: 1)
        let last = TrackingPeriod(.month, containing: first).nextStart?.adding(days: -1).day ?? 28
        return TrackingDay(year: year, month: month, day: min(day, last))
    }
}
