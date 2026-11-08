// ShownDayWatcher: notices that the day the app shows has changed
// (data_and_sync.md §8).

public import Foundation

/// The last day seen, for an app that polls: with nothing running no store
/// change marks the start of a new day, so views would keep yesterday's
/// "Today" until the next reload.
public struct ShownDayWatcher: Sendable {
    private var day: TrackingDay

    public init(calendar: TrackingCalendar, now: Date) {
        self.day = calendar.day(containing: now)
    }

    /// Whether the shown day differs from the last one seen, which `now`
    /// then becomes. A change of the start of day counts when it moves the day.
    public mutating func dayChanged(calendar: TrackingCalendar, now: Date) -> Bool {
        let today = calendar.day(containing: now)
        defer { day = today }
        return today != day
    }
}
