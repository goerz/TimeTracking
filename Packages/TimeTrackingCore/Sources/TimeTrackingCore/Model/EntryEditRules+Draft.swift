// EntryEditRules+Draft: the rules for an edited start and end that are
// saved together, as the iPhone's edit sheet does (spec_ios.md §2.7;
// spec_timer.md §4.2).

public import Foundation

extension EntryEditRules {
    /// Checks a start and end (`nil` for the running entry) at `now`: a
    /// start or end after `now` is refused first, then an end at or before
    /// the start.
    public static func check(start: Date, end: Date?, now: Date) -> Result<EntryEditResult, EntryEditError> {
        if start > now || (end.map { $0 > now } ?? false) {
            return .failure(.inFuture)
        }
        if let end, end <= start {
            return .failure(.endBeforeStart)
        }
        return .success(EntryEditResult(start: start, end: end))
    }

    /// Whether a stopped interval in `zone` is saved as more than one
    /// entry: it ends on a later day, and not exactly at midnight.
    public static func crossesMidnight(start: Date, end: Date, in zone: TimeZone) -> Bool {
        guard end > start else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return !calendar.isDate(start, inSameDayAs: end) && end != calendar.startOfDay(for: end)
    }
}
