// EntryEditRules: how the entry editor turns a field edit into a change
// (spec_timer.md §4.1, §4.2).

public import Foundation

/// A field edit of the entry editor.
public enum EntryFieldEdit: Hashable, Sendable {
    /// Start time of day, seconds after midnight.
    case start(Int)
    /// Stop time of day, seconds after midnight.
    case stop(Int)
    /// Duration in seconds.
    case duration(Int)
    /// The entry's date.
    case date(TrackingDay)
}

extension EntryFieldEdit {
    /// Stop, Duration, and Date are disabled for the running entry.
    public var isDisabledWhileRunning: Bool {
        switch self {
        case .start: false
        case .stop, .duration, .date: true
        }
    }
}

/// Why an edit is refused.
public enum EntryEditError: Error, Hashable, Sendable {
    /// "Entries cannot be in the future".
    case inFuture
    /// The start would not be before the stop.
    case endBeforeStart
    /// The field is disabled for a running entry.
    case runningEntry
}

/// The result of an edit: the new start and end.
public struct EntryEditResult: Hashable, Sendable {
    public var start: Date
    /// `nil` while running.
    public var end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    /// The change to pass to `update(_:_:)`.
    public var change: EntryChange {
        EntryChange(start: start, end: end)
    }
}

/// The editor's rules of §4.2.
public enum EntryEditRules {
    /// Applies `edit` to `entry` at `now`. Editing Start keeps Stop;
    /// editing Stop or Duration keeps Start; a Stop at or before Start
    /// means the next date; Date moves by whole days keeping the times. A
    /// result with a start or stop after `now` is refused.
    public static func apply(_ edit: EntryFieldEdit, to entry: TimeEntry, now: Date) -> Result<EntryEditResult, EntryEditError> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = entry.zone
        let midnight = calendar.startOfDay(for: entry.start)
        func time(_ seconds: Int, on day: Date) -> Date {
            calendar.date(byAdding: .second, value: seconds, to: day) ?? day
        }
        if entry.isRunning, edit.isDisabledWhileRunning {
            return .failure(.runningEntry)
        }
        var start = entry.start
        var end = entry.end
        switch edit {
        case let .start(seconds):
            start = time(seconds, on: midnight)
            if let end, start >= end {
                return .failure(.endBeforeStart)
            }
        case let .stop(seconds):
            var stop = time(seconds, on: midnight)
            if stop <= start {
                stop = time(seconds, on: calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight)
            }
            end = stop
        case let .duration(seconds):
            guard seconds > 0 else {
                return .failure(.endBeforeStart)
            }
            end = start + TimeInterval(seconds)
        case let .date(day):
            let days = entry.day.distance(to: day)
            start = calendar.date(byAdding: .day, value: days, to: start) ?? start
            end = end.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        }
        guard start <= now, (end ?? start) <= now else {
            return .failure(.inFuture)
        }
        return .success(EntryEditResult(start: start, end: end))
    }
}
