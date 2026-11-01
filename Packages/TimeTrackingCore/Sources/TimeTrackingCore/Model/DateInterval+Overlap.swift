// DateInterval+Overlap: the seconds two spans share, behind overlap
// resolution and calendar totals (spec_calendar.md §1.4, §2.6).

import Foundation

extension DateInterval {
    /// The seconds this interval shares with `other`; zero when they touch
    /// and negative (minus the gap) when they lie apart. Not clamped, so
    /// callers can compare against their own thresholds.
    func overlapDuration(with other: Self) -> TimeInterval {
        Swift.min(end, other.end).timeIntervalSince(Swift.max(start, other.start))
    }
}
