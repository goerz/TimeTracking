// CalendarEditing: drawing, moving, resizing, splitting, and duplicating in
// the Calendar, never past midnight or (for entries) after now
// (spec_calendar.md §2.2 to §2.5, §4.2).

public import Foundation

/// The outcome of a draw gesture.
public enum CalendarDrawResult: Sendable, Hashable {
    case interval(DateInterval)
    /// Under 1 minute: nothing is created.
    case tooShort
    /// A press below the now-line: "Entries can't be in the future".
    case future
}

/// The limits of gestures in one day column.
public struct CalendarEditing: Sendable {
    /// The minimum entry length everywhere.
    public static let minimumLength: TimeInterval = 60
    /// "Entries can't be in the future".
    public static let futureNotice = "Entries can't be in the future"

    public var day: DateInterval
    public var now: Date
    public var snap: CalendarSnap
    /// Entries stop at the now-line; time blocks do not.
    public var limitToNow: Bool

    public init(day: DateInterval, now: Date, snap: CalendarSnap, limitToNow: Bool = true) {
        self.day = day
        self.now = now
        self.snap = snap
        self.limitToNow = limitToNow
    }

    /// The latest allowed end: midnight, or the now-line for entries.
    public var upperLimit: Date {
        limitToNow ? min(day.end, now) : day.end
    }

    private func snapped(_ date: Date) -> Date {
        snap.snap(date, dayStart: day.start)
    }

    /// A drag from `from` to `to`, both ends snapped and clamped; a drag
    /// under a minute, or one that snaps to nothing, creates nothing.
    public func draw(from: Date, to: Date) -> CalendarDrawResult {
        if limitToNow, min(from, to) >= now {
            return .future
        }
        guard abs(to.timeIntervalSince(from)) >= Self.minimumLength else {
            return .tooShort
        }
        let upper = upperLimit
        let start = min(upper, max(day.start, snapped(min(from, to))))
        let end = min(upper, max(day.start, snapped(max(from, to))))
        guard end.timeIntervalSince(start) >= Self.minimumLength else {
            return .tooShort
        }
        return .interval(DateInterval(start: start, end: end))
    }

    /// A body drag by `offset`, the start snapped, the duration kept,
    /// clamped inside the day and before now; `nil` when it cannot fit
    /// (a drop on a future day).
    public func move(_ interval: DateInterval, by offset: TimeInterval) -> DateInterval? {
        let latestStart = upperLimit - interval.duration
        guard latestStart >= day.start else {
            return nil
        }
        let start = min(latestStart, max(day.start, snapped(interval.start + offset)))
        return DateInterval(start: start, duration: interval.duration)
    }

    /// A body drag of an entry crossing the day change, which no column
    /// holds: the start snapped, the duration kept, and only the now-line
    /// limits it; `nil` on a drop past it.
    public func moveAcrossDays(_ interval: DateInterval, by offset: TimeInterval) -> DateInterval? {
        let start = snapped(interval.start + offset)
        guard start < now else {
            return nil
        }
        return DateInterval(start: min(start, now - interval.duration), duration: interval.duration)
    }

    /// The running entry's start dragged to `date`: snapped, at most 1
    /// minute before now.
    public func moveRunningStart(to date: Date) -> Date {
        min(now - Self.minimumLength, max(day.start, snapped(date)))
    }

    /// The top edge dragged to `date`, down to 1 minute.
    public func resizeStart(_ interval: DateInterval, to date: Date) -> DateInterval {
        let start = min(interval.end - Self.minimumLength, max(day.start, snapped(date)))
        return DateInterval(start: start, end: interval.end)
    }

    /// The bottom edge dragged to `date`, down to 1 minute and not past
    /// midnight or the now-line.
    public func resizeEnd(_ interval: DateInterval, to date: Date) -> DateInterval {
        let end = max(interval.start + Self.minimumLength, min(upperLimit, snapped(date)))
        return DateInterval(start: interval.start, end: max(end, interval.start))
    }

    /// ⌥⌘↑ / ⌥⌘↓: the end by one snap step.
    public func lengthen(_ interval: DateInterval, steps: Int) -> DateInterval {
        let end = interval.end + Double(steps * snap.minutes * 60)
        return DateInterval(start: interval.start, end: max(interval.start + Self.minimumLength, min(upperLimit, end)))
    }

    /// Split Here: refused within 1 minute of either end (the running
    /// entry's end is now).
    public static func canSplit(start: Date, end: Date?, at time: Date, now: Date) -> Bool {
        time.timeIntervalSince(start) >= minimumLength && (end ?? now).timeIntervalSince(time) >= minimumLength
    }

    /// Duplicate to Next Day: the same wall-clock times the next day,
    /// refused unless that interval is entirely past.
    public static func duplicateToNextDay(_ interval: DateInterval, in zone: TimeZone, now: Date) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let start = calendar.date(byAdding: .day, value: 1, to: interval.start) else {
            return nil
        }
        let copy = DateInterval(start: start, duration: interval.duration)
        return copy.end <= now ? copy : nil
    }
}

/// Splitting an interval into one piece per day (§1.2): events and time
/// blocks crossing midnight are drawn as pieces that move together.
public struct CalendarPiece<ID: Hashable & Sendable>: Sendable, Hashable {
    public var id: ID
    public var day: TrackingDay
    /// The part of the whole interval on `day`.
    public var interval: DateInterval
    /// The whole interval (moves apply to it).
    public var whole: DateInterval

    /// The pieces of `whole` on each day it touches.
    public static func pieces(of whole: DateInterval, id: ID, calendar: TrackingCalendar) -> [Self] {
        var result: [Self] = []
        var day = calendar.day(containing: whole.start)
        while true {
            let dayInterval = calendar.interval(of: day)
            guard dayInterval.start < whole.end || (whole.duration == 0 && dayInterval.contains(whole.start)) else {
                break
            }
            let start = max(whole.start, dayInterval.start)
            let end = min(whole.end, dayInterval.end)
            if end > start || whole.duration == 0 {
                result.append(Self(id: id, day: day, interval: DateInterval(start: start, end: max(start, end)), whole: whole))
            }
            if whole.duration == 0 {
                break
            }
            day = day.adding(days: 1)
        }
        return result
    }

    /// The whole interval after dragging this piece by `offset`.
    public func moved(by offset: TimeInterval) -> DateInterval {
        DateInterval(start: whole.start + offset, duration: whole.duration)
    }
}
