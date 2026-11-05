// EntryEditRules: how the entry editor turns a field edit into a change
// (spec_timer.md §4.1, §4.2).

public import Foundation

/// A field edit of the entry editor.
public enum EntryFieldEdit: Hashable, Sendable {
    /// Start as a wall-clock time of day, in seconds (`9 * 3600` is 09:00).
    case start(Int)
    /// Stop as a wall-clock time of day, in seconds.
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

    /// The change to pass to `update(_:_:)` for an editor showing `entry`:
    /// only the times that differ from it, so a time another device or
    /// window changed since the editor read `entry` is not written back.
    public func change(from entry: TimeEntry) -> EntryChange {
        EntryChange(start: start != entry.start ? start : nil, end: end != entry.end ? end : nil)
    }

    /// The change for an editor showing `entry`, or `nil` when neither time differs.
    public func changeIfAny(from entry: TimeEntry) -> EntryChange? {
        let change = change(from: entry)
        return change.start == nil && change.end == nil ? nil : change
    }
}

/// The editor's rules of §4.2.
public enum EntryEditRules {
    /// Applies `edit` to `entry` at `now`. Editing Start keeps Stop;
    /// editing Stop or Duration keeps Start; a Stop at or before Start
    /// means the next date; Date moves by whole days keeping the times. The
    /// fields show whole minutes, so a Start or Stop without seconds keeps
    /// the stored ones. A result with a start or stop after `now` is refused.
    public static func apply(_ edit: EntryFieldEdit, to entry: TimeEntry, now: Date) -> Result<EntryEditResult, EntryEditError> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = entry.zone
        let midnight = calendar.startOfDay(for: entry.start)
        // Wall-clock components, not elapsed seconds: a DST day has 23 or
        // 25 hours. A time the change skips is the first instant after it.
        func time(_ seconds: Int, on day: Date) -> Date {
            calendar.date(bySettingHour: seconds / 3600, minute: seconds / 60 % 60, second: seconds % 60, of: day) ?? day
        }
        func keepingSeconds(_ seconds: Int, of stored: Date) -> Int {
            seconds.isMultiple(of: 60) ? seconds + calendar.component(.second, from: stored) : seconds
        }
        if entry.isRunning, edit.isDisabledWhileRunning {
            return .failure(.runningEntry)
        }
        var start = entry.start
        var end = entry.end
        switch edit {
        case let .start(seconds):
            start = time(keepingSeconds(seconds, of: entry.start), on: midnight)
            if let end, start >= end {
                return .failure(.endBeforeStart)
            }
        case let .stop(seconds):
            let seconds = keepingSeconds(seconds, of: end ?? start)
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
