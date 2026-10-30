// TrackerDuration: the duration strings of settings.toml ("30s", "5m", "3h")
// (spec_activity_tracking.md §7.1).

public import Foundation

/// Parses and formats the durations of `settings.toml`.
public enum TrackerDuration {
    private static let units: [Character: TimeInterval] = ["s": 1, "m": 60, "h": 3600, "d": 24 * 3600]

    /// Parses one or more `<number><unit>` parts with the units `s`, `m`,
    /// `h`, and `d`, e.g. `"30s"`, `"5m"`, `"1h30m"`, or a bare number of
    /// seconds. Returns `nil` for anything else.
    public static func parse(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }
        var total: TimeInterval = 0
        var number = ""
        var sawPart = false
        for character in trimmed {
            if character.isNumber || character == "." {
                number.append(character)
            } else if let unit = units[character], let value = TimeInterval(number) {
                total += value * unit
                number = ""
                sawPart = true
            } else {
                return nil
            }
        }
        return sawPart && number.isEmpty ? total : nil
    }

    /// Formats whole seconds with the largest unit that divides them:
    /// 3 hours as `"3h"`, 5400 as `"90m"`, 30 as `"30s"`.
    public static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole > 0, whole.isMultiple(of: 3600) {
            return "\(whole / 3600)h"
        }
        if whole > 0, whole.isMultiple(of: 60) {
            return "\(whole / 60)m"
        }
        return "\(whole)s"
    }
}
