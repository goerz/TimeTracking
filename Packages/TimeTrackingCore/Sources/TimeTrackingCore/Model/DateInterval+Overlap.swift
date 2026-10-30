// DateInterval+Overlap: the seconds two spans share, behind overlap
// resolution, calendar totals, and suggestions (spec_planner_calendar.md
// §1.4, §2.6, §3.5, §5.1).

import Foundation

extension DateInterval {
    /// The seconds this interval shares with `other`; zero when they touch
    /// and negative (minus the gap) when they lie apart. Not clamped, so
    /// callers can compare against their own thresholds.
    func overlapDuration(with other: Self) -> TimeInterval {
        overlapDuration(start: other.start, end: other.end)
    }

    /// The seconds this interval shares with the span from `start` to `end`,
    /// unclamped like `overlapDuration(with:)`. The span may end before it
    /// starts (its overlap is then negative).
    func overlapDuration(start: Date, end: Date) -> TimeInterval {
        Swift.min(self.end, end).timeIntervalSince(Swift.max(self.start, start))
    }
}
