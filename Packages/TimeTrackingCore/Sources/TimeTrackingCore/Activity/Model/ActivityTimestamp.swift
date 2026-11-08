// ActivityTimestamp: the public face of the logs' offset-free local times
// (activity_tracking.md §4.2 to §4.4).

public import Foundation

/// Formats and parses the wall-clock times `YYYY-MM-DDTHH:MM:SS` of the
/// block log, `current.json`, and the agent's Samples.
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

    /// `YYYY-MM-DDTHH:MM:SS±HH:MM`, the form of the block log's `s` and `e`.
    public static func textWithOffset(_ date: Date, utcOffset: Int) -> String {
        text(date, utcOffset: utcOffset) + offsetText(utcOffset)
    }

    /// The instant and offset of `YYYY-MM-DDTHH:MM:SS±HH:MM` (or `Z`), or
    /// `nil` for any other text.
    public static func parseWithOffset(_ text: some StringProtocol) -> (date: Date, utcOffset: Int)? {
        guard text.count > 19, let local = LocalTimestamp(text: text.prefix(19)),
              let offset = LocalTimestamp.parseOffset(String(text.dropFirst(19)))
        else {
            return nil
        }
        return (local.date(utcOffset: offset), offset)
    }

    /// `±HH:MM` of `seconds` east of UTC.
    public static func offsetText(_ seconds: Int) -> String {
        LocalTimestamp.offsetText(seconds)
    }

    /// Seconds east of UTC of `Z`, `±HH:MM`, or `±HHMM`.
    public static func parseOffset(_ text: String) -> Int? {
        LocalTimestamp.parseOffset(text)
    }

    /// Local midnight at the start of the local date of `date` in `timeZone`.
    public static func startOfDay(_ date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }
}
