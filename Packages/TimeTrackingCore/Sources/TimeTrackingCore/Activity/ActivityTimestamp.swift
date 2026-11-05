// ActivityTimestamp: the public face of the logs' offset-free local times
// (activity_tracking.md §4.2 to §4.4).

public import Foundation

/// Formats and parses the wall-clock times `YYYY-MM-DDTHH:MM:SS` of the
/// block log, the detail log, `current.json`, and the agent's samples.
public enum ActivityTimestamp {
    /// The wall-clock text of `date` at `utcOffset` seconds east of UTC.
    public static func text(_ date: Date, utcOffset: Int) -> String {
        LocalTimestamp(date: date, utcOffset: utcOffset).text
    }

    /// The wall-clock text of `date` in `timeZone`.
    public static func text(_ date: Date, timeZone: TimeZone) -> String {
        text(date, utcOffset: timeZone.secondsFromGMT(for: date))
    }

    /// The local date `YYYY-MM-DD` of `date` at `utcOffset`.
    public static func day(_ date: Date, utcOffset: Int) -> String {
        LocalTimestamp(date: date, utcOffset: utcOffset).dayKey
    }

    /// The local date `YYYY-MM-DD` of `date` in `timeZone`.
    public static func day(_ date: Date, timeZone: TimeZone) -> String {
        day(date, utcOffset: timeZone.secondsFromGMT(for: date))
    }

    /// The instant of a wall-clock text at `utcOffset`, or `nil` if malformed.
    public static func date(_ text: some StringProtocol, utcOffset: Int) -> Date? {
        LocalTimestamp(text: text)?.date(utcOffset: utcOffset)
    }

    /// The instant of a wall-clock text in `timeZone`, or of an RFC 3339
    /// text with an offset.
    public static func date(_ text: String, timeZone: TimeZone) -> Date? {
        LocalTimestamp.instant(text, timeZone: timeZone)
    }

    /// `±HH:MM` of `seconds` east of UTC.
    public static func offsetText(_ seconds: Int) -> String {
        LocalTimestamp.offsetText(seconds)
    }

    /// Seconds east of UTC of `Z`, `±HH:MM`, or `±HHMM`.
    public static func parseOffset(_ text: String) -> Int? {
        LocalTimestamp.parseOffset(text)
    }

    /// Local midnight at the start of the day after the local date of
    /// `date` in `timeZone`.
    public static func nextMidnight(after date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Local midnight at the start of the local date of `date` in `timeZone`.
    public static func startOfDay(_ date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }
}
