// DayBoundaries: where each local date starts, fixed at the UTC offset in
// effect when a Sample first marked it (activity_tracking.md §4.1).

public import Foundation

/// The 00:00 of every date: at its stored offset, or else at the offset of
/// `zone` at the start of that date. A date and the next agree on the
/// instant between them, so a change of zone never moves a block from one
/// file to another.
public struct DayBoundaries: Sendable, Hashable {
    public var zone: TimeZone
    public var offsets: [TrackingDay: Int]

    public init(zone: TimeZone, offsets: [TrackingDay: Int] = [:]) {
        self.zone = zone
        self.offsets = offsets
    }

    /// The offset of `day`'s 00:00: the stored one, else the zone's at the
    /// start of that date (the first instant after a midnight DST skips).
    public func offset(of day: TrackingDay) -> Int {
        if let stored = offsets[day] {
            return stored
        }
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        guard let start = calendar.date(from: components) else {
            return zone.secondsFromGMT()
        }
        return zone.secondsFromGMT(for: calendar.startOfDay(for: start))
    }

    /// The instant `day` starts: its 00:00 at its offset.
    public func start(of day: TrackingDay) -> Date {
        LocalTimestamp(year: day.year, month: day.month, day: day.day, hour: 0, minute: 0, second: 0).date(utcOffset: offset(of: day))
    }

    /// The date `time` lies on.
    public func day(containing time: Date) -> TrackingDay {
        let local = calendar.dateComponents([.year, .month, .day], from: time)
        let guess = TrackingDay(year: local.year ?? 1970, month: local.month ?? 1, day: local.day ?? 1)
        // A stored offset other than the zone's moves the line by less than a day.
        if time < start(of: guess) {
            return guess.adding(days: -1)
        }
        if time >= start(of: guess.adding(days: 1)) {
            return guess.adding(days: 1)
        }
        return guess
    }

    /// Fixes `day`'s offset if it has none yet; returns whether it did.
    @discardableResult
    public mutating func fix(_ day: TrackingDay) -> Bool {
        guard offsets[day] == nil else {
            return false
        }
        offsets[day] = offset(of: day)
        return true
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
