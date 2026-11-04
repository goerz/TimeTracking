// HealthPeriod+Label: the duration label on a sleep or workout line in the
// Calendar's Activity column (spec_calendar.md §3.1).

import Foundation

extension HealthPeriod {
    /// The day whose piece of the line carries the label: the day the
    /// period ends (a night's sleep is labeled on the morning it ends).
    public func labelDay(in calendar: TrackingCalendar) -> TrackingDay {
        calendar.day(containing: end > start ? end.addingTimeInterval(-1) : start)
    }

    /// The whole period's duration, across midnight ("7h 10m").
    public var durationText: String {
        ActivityText.duration(Int(interval.duration))
    }
}
