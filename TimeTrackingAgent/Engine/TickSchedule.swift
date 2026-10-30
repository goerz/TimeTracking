// TickSchedule: when the regular ticks fire (spec_activity_tracking.md §2.1).

import Foundation

/// Regular ticks every 30 seconds from the start; event ticks in between do
/// not move the schedule. A tick that comes late (after sleep) fires once
/// and the schedule continues from it.
nonisolated struct TickSchedule: Hashable, Sendable {
    let interval: TimeInterval
    private(set) var next: Date

    init(start: Date, interval: TimeInterval = 30) {
        self.interval = interval
        self.next = start
    }

    /// Whether a regular tick is due at `now`.
    func isDue(at now: Date) -> Bool {
        now >= next
    }

    /// Marks the tick due at `now` as taken.
    mutating func fired(at now: Date) {
        next = next.addingTimeInterval(interval)
        if next <= now {
            next = now.addingTimeInterval(interval)
        }
    }
}
