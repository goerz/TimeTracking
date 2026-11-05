// CalendarViewport: the Calendar's horizontal strip of days, with the day
// width as horizontal zoom, a free scroll position, the arrows' snapping,
// and the days it shows (spec_calendar.md §1.2).

import Foundation

/// A column of a day, as a drag's pointer finds it (§2.4, §4.2).
public struct CalendarDropTarget: Sendable, Hashable {
    public var day: TrackingDay
    public var column: CalendarColumn

    public init(day: TrackingDay, column: CalendarColumn) {
        self.day = day
        self.column = column
    }
}

/// The days across the viewport. A day is `dayWidth` points wide whatever
/// the window's size, so the window decides how many days show, and the
/// days at either edge may be cut off.
public struct CalendarViewport: Sendable, Hashable {
    /// The day widths the slider and the keys allow.
    public static let dayWidthRange = 96.0 ... 1600.0
    public static let defaultDayWidth = 260.0
    /// ⌥⌘] and ⌥⌘[ multiply or divide the day width by this.
    public static let dayWidthStep = 1.25

    /// The leftmost day, of which `offset` lies left of the viewport.
    public private(set) var firstDay: TrackingDay
    /// The hidden part of `firstDay`, in days, in 0 ..< 1.
    public private(set) var offset: Double
    public private(set) var dayWidth: Double
    /// The points available to the days (the window less the time axis).
    public private(set) var width: Double

    public init(firstDay: TrackingDay, offset: Double = 0, dayWidth: Double = defaultDayWidth, width: Double = 0) {
        self.firstDay = firstDay
        self.offset = 0
        self.dayWidth = Self.clamped(dayWidth)
        self.width = max(0, width)
        move(by: offset)
    }

    public static func clamped(_ dayWidth: Double) -> Double {
        min(dayWidthRange.upperBound, max(dayWidthRange.lowerBound, dayWidth))
    }

    /// The viewport's width in days.
    public var span: Double {
        width / dayWidth
    }

    /// The whole days that fit, at least one: the step of ⇧← and ⇧→ and
    /// the days ⌘T centers today among.
    public var wholeDays: Int {
        max(1, Int((span + 1e-9).rounded(.down)))
    }

    /// Every day with a part in the viewport, left to right.
    public var touchedDays: [TrackingDay] {
        let count = max(1, Int((offset + span - 1e-9).rounded(.up)))
        return (0 ..< count).map { firstDay.adding(days: $0) }
    }

    /// The days at least half visible (or, for a day wider than the
    /// viewport, covering half of it): the subtitle, the date menu, and the
    /// summary strip count these. Never empty.
    public var shownDays: [TrackingDay] {
        let threshold = min(dayWidth, max(width, 1)) / 2
        let shown = touchedDays.filter { visibleWidth(of: $0) >= threshold - 1e-6 }
        return shown.isEmpty ? [day(atX: width / 2)] : shown
    }

    /// The points of `day` inside the viewport.
    public func visibleWidth(of day: TrackingDay) -> Double {
        let left = x(of: day)
        return max(0, min(left + dayWidth, width) - max(left, 0))
    }

    /// The left edge of `day` relative to the viewport's left edge.
    public func x(of day: TrackingDay) -> Double {
        (Double(firstDay.distance(to: day)) - offset) * dayWidth
    }

    /// The day at `x` points from the viewport's left edge.
    public func day(atX x: Double) -> TrackingDay {
        firstDay.adding(days: Int((offset + x / dayWidth).rounded(.down)))
    }

    /// The column at `x` points from the viewport's left edge, of the
    /// visible `columns`; `nil` outside the viewport.
    public func target(atX x: Double, columns: [CalendarColumn]) -> CalendarDropTarget? {
        guard x >= 0, x < width else {
            return nil
        }
        let day = day(atX: x)
        let inDay = x - self.x(of: day)
        let column = columns.last { CalendarColumn.x(of: $0, dayWidth: dayWidth, visible: columns) <= inDay }
        return column.map { CalendarDropTarget(day: day, column: $0) }
    }

    /// A sideways scroll by `points` (positive: later), free of snapping.
    public mutating func scroll(byPoints points: Double) {
        move(by: points / dayWidth)
    }

    /// The arrows: `days` forward or back, snapped so that a day starts at
    /// the left edge. From a cut-off day the first step goes to the nearer
    /// boundary in that direction.
    public mutating func step(days: Int) {
        guard days != 0 else {
            return
        }
        let target = days > 0 ? firstDay.adding(days: days) : firstDay.adding(days: days + (offset > 1e-9 ? 1 : 0))
        show(target)
    }

    /// `day` at the left edge.
    public mutating func show(_ day: TrackingDay) {
        firstDay = day
        offset = 0
    }

    /// ⌘T: `today` at position ⌈n / 2⌉ of the `n` whole days that fit,
    /// with a day starting at the left edge.
    public mutating func center(_ today: TrackingDay) {
        show(CalendarStrip.firstDay(centering: today, visibleDays: wholeDays))
    }

    /// A new window width; the left edge stays.
    public mutating func setWidth(_ width: Double) {
        self.width = max(0, width)
    }

    /// The horizontal zoom, keeping the time at `anchor` points from the
    /// left edge in place (the viewport's center when nil).
    public mutating func setDayWidth(_ dayWidth: Double, anchor: Double? = nil) {
        let anchor = anchor ?? width / 2
        let anchorDays = offset + anchor / self.dayWidth
        self.dayWidth = Self.clamped(dayWidth)
        offset = 0
        move(by: anchorDays - anchor / self.dayWidth)
    }

    /// `day` alone: its width becomes the viewport's, and it starts at the
    /// left edge.
    public mutating func showAlone(_ day: TrackingDay) {
        if width > 0 {
            dayWidth = Self.clamped(width)
        }
        show(day)
    }

    /// The slider's position, 0 ... 1 on a logarithmic scale.
    public static func sliderValue(dayWidth: Double) -> Double {
        let range = dayWidthRange
        return log(clamped(dayWidth) / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    /// The day width at a slider position.
    public static func dayWidth(sliderValue: Double) -> Double {
        let range = dayWidthRange
        return clamped(range.lowerBound * pow(range.upperBound / range.lowerBound, min(1, max(0, sliderValue))))
    }

    /// Moves the left edge by `days` and normalizes `offset` into 0 ..< 1.
    private mutating func move(by days: Double) {
        let position = offset + days
        let whole = Int(position.rounded(.down))
        firstDay = firstDay.adding(days: whole)
        offset = position - Double(whole)
        if offset >= 1 - 1e-9 {
            firstDay = firstDay.adding(days: 1)
            offset = 0
        }
    }
}
