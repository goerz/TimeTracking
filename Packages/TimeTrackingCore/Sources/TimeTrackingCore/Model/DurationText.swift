// DurationText: durations and times of day as the Timer window, menu bar, and
// entry editor write and read them (spec_timer_window.md §2, §4.1, §5.1;
// spec_menubar.md §1.1).

import Foundation

/// Formats and parses durations and times of day. Formatting truncates to
/// whole seconds; durations are never rounded.
public enum DurationText {
    /// `h:mm:ss`, hours without a leading zero (`0:42:27`, `25:00:00`).
    public static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /// `h:mm` (`0:04`, `13:05`), hours growing past 24.
    public static func hoursMinutes(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 3600, seconds / 60 % 60)
    }

    /// `m:ss`, or `h:mm:ss` from one hour (the Pomodoro countdown).
    public static func countdown(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds >= 3600 {
            return clock(seconds)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Always `m:ss` with minutes growing past 59 (the menu bar countdown).
    public static func minutesSeconds(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// `+m:ss` (`+h:mm:ss` from one hour), counting up in overtime.
    public static func overtime(_ seconds: Int) -> String {
        "+" + countdown(seconds)
    }

    /// Parses a duration: `h:mm:ss`, `h:mm` (`1:30`), `25m`, `1h 30m`,
    /// `1h30m`, `90s`, or a bare number of minutes; `nil` otherwise.
    public static func parseDuration(_ text: String) -> Int? {
        let text = text.trimmed.lowercased()
        guard !text.isEmpty else {
            return nil
        }
        if text.contains(":") {
            return parseColonDuration(text)
        }
        if let minutes = Int(text) {
            return minutes >= 0 ? minutes * 60 : nil
        }
        return parseUnitDuration(text)
    }

    /// `h:mm` or `h:mm:ss`.
    private static func parseColonDuration(_ text: String) -> Int? {
        let values = text.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) ?? -1 }
        guard values.allSatisfy({ $0 >= 0 }), values.dropFirst().allSatisfy({ $0 < 60 }) else {
            return nil
        }
        switch values.count {
        case 2: return values[0] * 3600 + values[1] * 60
        case 3: return values[0] * 3600 + values[1] * 60 + values[2]
        default: return nil
        }
    }

    /// `1h 30m`, `25m`, `90s`.
    private static func parseUnitDuration(_ text: String) -> Int? {
        let factors: [Character: Int] = ["h": 3600, "m": 60, "s": 1]
        var total = 0
        var number = ""
        var sawUnit = false
        for character in text where !character.isWhitespace {
            if character.isASCII, character.isNumber {
                number.append(character)
                continue
            }
            guard let value = Int(number), let factor = factors[character] else {
                return nil
            }
            total += value * factor
            number = ""
            sawUnit = true
        }
        return sawUnit && number.isEmpty ? total : nil
    }

    /// Parses a time of day: `9:1` reads as 09:10, `9:10`, `0910`, `9`,
    /// `14:02:30`, and 12-hour forms with `am`/`pm` (`9:10 pm`). Returns
    /// seconds after midnight, or `nil`.
    public static func parseTimeOfDay(_ text: String) -> Int? {
        var text = text.trimmed.lowercased().replacingOccurrences(of: ".", with: "")
        var meridiem: Int?
        for (suffix, offset) in [("am", 0), ("pm", 12), ("a", 0), ("p", 12)] where text.hasSuffix(suffix) {
            meridiem = offset
            text = String(text.dropLast(suffix.count)).trimmed
            break
        }
        var parts: [String] = if text.contains(":") {
            text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        } else if text.count > 2, text.allSatisfy(\.isNumber) {
            [String(text.dropLast(2)), String(text.suffix(2))]
        } else {
            [text]
        }
        guard (1 ... 3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        // A single minute digit is the tens digit: "9:1" is 09:10.
        if parts.count >= 2, parts[1].count == 1 {
            parts[1] += "0"
        }
        let values = parts.compactMap { Int($0) }
        var hour = values[0]
        let minute = values.count > 1 ? values[1] : 0
        let second = values.count > 2 ? values[2] : 0
        if let meridiem {
            guard (1 ... 12).contains(hour) else {
                return nil
            }
            hour = hour % 12 + meridiem
        }
        guard (0 ..< 24).contains(hour), (0 ..< 60).contains(minute), (0 ..< 60).contains(second) else {
            return nil
        }
        return hour * 3600 + minute * 60 + second
    }
}
