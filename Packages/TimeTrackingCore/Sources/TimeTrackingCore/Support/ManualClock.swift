// ManualClock: a clock that moves only when told to (architecture.md §3.3, §3.4).

public import Foundation
import Synchronization

/// A clock whose time changes only through `set(_:)` and `advance(by:)`.
///
/// Tests use it in place of sleeping. It is also the clock of a process
/// started with a fixed `TIMETRACKING_NOW`.
public final class ManualClock: Clock {
    private let current: Mutex<Date>

    /// Creates a clock that reports `now` until it is moved.
    public init(_ now: Date) {
        self.current = Mutex(now)
    }

    public var now: Date {
        current.withLock { $0 }
    }

    /// Moves the clock to `date`, which may be earlier than the current time.
    public func set(_ date: Date) {
        current.withLock { $0 = date }
    }

    /// Moves the clock forward by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        current.withLock { $0 += interval }
    }
}

extension ManualClock {
    /// The fixed test instant of the fixtures, 2024-03-14T10:00:00 local
    /// time (a Thursday), in `timeZone`.
    public static func fixtureNow(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: 2024, month: 3, day: 14, hour: 10)
        // The components are valid in every time zone, so the date exists.
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_710_410_400)
    }

    /// A clock at `fixtureNow(in:)`.
    public static func fixture(in timeZone: TimeZone = .current) -> ManualClock {
        ManualClock(fixtureNow(in: timeZone))
    }
}
