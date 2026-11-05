// CalendarDayAxis: the Calendar section's time axis, with its zoom, the
// strip's labels, columns, and snapping (spec_calendar.md §1).

public import Foundation

/// Vertical zoom (§1.3).
public enum CalendarZoom {
    public static let defaultPointsPerHour = 72.0
    public static let range = 24.0 ... 480.0
    public static let step = 1.25

    public static func clamped(_ pointsPerHour: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, pointsPerHour))
    }

    /// ⌘+.
    public static func zoomedIn(_ pointsPerHour: Double) -> Double {
        clamped(pointsPerHour * step)
    }

    /// ⌘−.
    public static func zoomedOut(_ pointsPerHour: Double) -> Double {
        clamped(pointsPerHour / step)
    }

    /// The scroll offset after a zoom that keeps the time under `anchor`
    /// (a y position in the viewport) in place, at most `maximum`.
    public static func scrollOffset(
        _ offset: Double,
        anchor: Double,
        from old: Double,
        to new: Double,
        maximum: Double = .infinity
    ) -> Double {
        min(max(0, maximum), max(0, (offset + anchor) * new / old - anchor))
    }

    /// The point of the viewport a zoom keeps in place: a pinch's `pinchY`,
    /// else the now-line at `nowY` (from the content's top) while it is in
    /// view, else the viewport's center.
    public static func anchor(offset: Double, viewportHeight: Double, nowY: Double?, pinchY: Double?) -> Double {
        let now = nowY.map { $0 - offset }.flatMap { (0 ... viewportHeight).contains($0) ? $0 : nil }
        return pinchY ?? now ?? viewportHeight / 2
    }

    /// Minutes between hour labels.
    public static func labelMinutes(pointsPerHour: Double) -> Int {
        switch pointsPerHour {
        case ..<36: 120
        case ...120: 60
        case ...240: 30
        default: 15
        }
    }

    /// How a card of `height` points draws.
    public enum CardStyle: Sendable, Hashable {
        /// A bare color bar (under 14 points).
        case bar
        /// One line, title and duration (under 28 points).
        case oneLine
        case full
    }

    public static func cardStyle(height: Double) -> CardStyle {
        height < 14 ? .bar : height < 28 ? .oneLine : .full
    }
}

/// One day column's time axis: midnight to midnight in the zone, 23 to 25
/// hours on daylight-saving days.
public struct CalendarDayAxis: Sendable, Hashable {
    public var day: TrackingDay
    public var interval: DateInterval
    public var pointsPerHour: Double

    public init(day: TrackingDay, calendar: TrackingCalendar, pointsPerHour: Double) {
        self.day = day
        self.interval = calendar.interval(of: day)
        self.pointsPerHour = pointsPerHour
    }

    /// The column's height in points.
    public var height: Double {
        interval.duration * pointsPerHour / 3600
    }

    /// The offset of `date` from the column's top.
    public func y(_ date: Date) -> Double {
        date.timeIntervalSince(interval.start) * pointsPerHour / 3600
    }

    /// The time at offset `y`, clamped to the day.
    public func date(atY y: Double) -> Date {
        let seconds = min(interval.duration, max(0, y * 3600 / pointsPerHour))
        return interval.start + seconds
    }

    /// The top and height of `range` clipped to the day, or `nil` outside it.
    public func frame(of range: DateInterval) -> (y: Double, height: Double)? {
        let start = max(range.start, interval.start)
        let end = min(range.end, interval.end)
        guard end >= start, start < interval.end || range.duration == 0 else {
            return nil
        }
        return (y(start), end.timeIntervalSince(start) * pointsPerHour / 3600)
    }

    /// The offset of `date` from the top of the card of `card`, which the
    /// column clips (§3.1).
    public func offset(of date: Date, inCardOf card: DateInterval) -> Double {
        y(date) - y(max(card.start, interval.start))
    }

    /// The now-line's offset on today only (§1.5).
    public func nowOffset(_ now: Date) -> Double? {
        now >= interval.start && now < interval.end ? y(now) : nil
    }
}

/// The labels and the Today position of the strip of days (§1.1, §1.2).
public enum CalendarStrip {
    /// The first day that puts `today` at position ⌈visibleDays / 2⌉ (⌘T).
    public static func firstDay(centering today: TrackingDay, visibleDays: Int) -> TrackingDay {
        today.adding(days: -((visibleDays + 1) / 2 - 1))
    }

    /// The date menu's title (§1.1): "Today" while today is visible, else
    /// the visible days, "Oct 19 – 23", "Oct 30 – Nov 3", or "Oct 19".
    public static func menuTitle(first: TrackingDay, count: Int, today: TrackingDay) -> String {
        let last = first.adding(days: max(count, 1) - 1)
        if (first ... last).contains(today) {
            return "Today"
        }
        let start = "\(DayText.shortMonth(first)) \(first.day)"
        guard count > 1 else {
            return start
        }
        let sameMonth = first.month == last.month && first.year == last.year
        return "\(start) – \(sameMonth ? "" : "\(DayText.shortMonth(last)) ")\(last.day)"
    }

    /// "Mon, Oct 26 – Fri, Oct 30 · W44".
    public static func label(first: TrackingDay, count: Int) -> String {
        let last = first.adding(days: max(count, 1) - 1)
        let text = { (day: TrackingDay) in "\(DayText.shortWeekday(day)), \(DayText.shortMonth(day)) \(day.day)" }
        let weeks = first.isoWeek.week == last.isoWeek.week ? "W\(first.isoWeek.week)" : "W\(first.isoWeek.week)–\(last.isoWeek.week)"
        return count <= 1 ? "\(text(first)) · \(weeks)" : "\(text(first)) – \(text(last)) · \(weeks)"
    }
}

/// The three columns of a day (§1.4).
public enum CalendarColumn: String, Sendable, Hashable, CaseIterable, Codable {
    case activity
    case tracked
    case calendar

    public var weight: Double {
        switch self {
        case .activity: 1
        case .tracked: 2
        case .calendar: 1.5
        }
    }

    /// Each visible column's width, `dayWidth` split by weight.
    public static func widths(dayWidth: Double, visible: [Self]) -> [Self: Double] {
        let total = visible.reduce(0) { $0 + $1.weight }
        return Dictionary(uniqueKeysWithValues: visible.map { ($0, dayWidth * $0.weight / max(total, 1)) })
    }

    /// A column under 72 points draws its cards as bars.
    public static func drawsBars(width: Double) -> Bool {
        width < 72
    }

    /// Column names show while the day is at least 240 points wide.
    public static func showsNames(dayWidth: Double) -> Bool {
        dayWidth >= 240
    }
}

/// Snapping to `minutes` from midnight (§2.3).
public struct CalendarSnap: Sendable, Hashable {
    public var minutes: Int

    public init(minutes: Int) {
        self.minutes = max(1, minutes)
    }

    /// The steps the Snap to setting allows.
    public static let choices = [1, 5, 10, 15]

    /// `date` rounded to the nearest step after `dayStart`.
    public func snap(_ date: Date, dayStart: Date) -> Date {
        let step = Double(minutes * 60)
        let offset = date.timeIntervalSince(dayStart)
        return dayStart + (offset / step).rounded() * step
    }
}
