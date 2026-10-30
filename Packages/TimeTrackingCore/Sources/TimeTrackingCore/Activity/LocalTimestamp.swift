// LocalTimestamp: the offset-free wall-clock times of the activity logs
// (spec_activity_tracking.md §4.2, §4.4).

import Foundation

/// A wall-clock time `YYYY-MM-DDTHH:MM:SS` as the block log, the detail log,
/// and `current.json` write it.
///
/// The block log converts these with the latest header's fixed offset, so
/// the arithmetic here is calendar-free and does not depend on the
/// machine's time zone.
struct LocalTimestamp: Hashable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int

    /// Parses exactly `YYYY-MM-DDTHH:MM:SS`.
    init?(text: some StringProtocol) {
        let bytes = Array(text.utf8)
        guard bytes.count == 19,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              bytes[10] == UInt8(ascii: "T") || bytes[10] == UInt8(ascii: " "),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":")
        else {
            return nil
        }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(bytes[index]) - Int(UInt8(ascii: "0"))
                guard (0 ... 9).contains(digit) else {
                    return nil
                }
                value = value * 10 + digit
            }
            return value
        }
        guard let parsedYear = number(0 ..< 4), let parsedMonth = number(5 ..< 7), let parsedDay = number(8 ..< 10),
              let parsedHour = number(11 ..< 13), let parsedMinute = number(14 ..< 16), let parsedSecond = number(17 ..< 19),
              (1 ... 12).contains(parsedMonth),
              (1 ... Self.daysInMonth(year: parsedYear, month: parsedMonth)).contains(parsedDay),
              (0 ... 23).contains(parsedHour), (0 ... 59).contains(parsedMinute), (0 ... 59).contains(parsedSecond)
        else {
            return nil
        }
        self.year = parsedYear
        self.month = parsedMonth
        self.day = parsedDay
        self.hour = parsedHour
        self.minute = parsedMinute
        self.second = parsedSecond
    }

    /// The wall-clock time of `date` at a fixed offset from UTC, in seconds.
    init(date: Date, utcOffset: Int) {
        let local = Int(date.timeIntervalSince1970.rounded(.down)) + utcOffset
        let days = Self.floorDivide(local, by: 24 * 3600)
        let seconds = local - days * 24 * 3600
        var shifted = days + 719_468
        let era = Self.floorDivide(shifted, by: 146_097)
        shifted -= era * 146_097
        let yearOfEra = (shifted - shifted / 1460 + shifted / (365 * 100 + 24) - shifted / 146_096) / 365
        let dayOfYear = shifted - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let civilMonth = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        self.year = yearOfEra + era * 400 + (civilMonth <= 2 ? 1 : 0)
        self.month = civilMonth
        self.day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        self.hour = seconds / 3600
        self.minute = seconds % 3600 / 60
        self.second = seconds % 60
    }

    /// The instant of this wall-clock time at a fixed offset from UTC.
    func date(utcOffset: Int) -> Date {
        let seconds = Self.daysFromCivil(year: year, month: month, day: day) * 24 * 3600
            + hour * 3600 + minute * 60 + second - utcOffset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// The instant of this wall-clock time in `timeZone`.
    func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: components)
    }

    /// `YYYY-MM-DDTHH:MM:SS`.
    var text: String {
        "\(dayKey)T\(Self.pad(hour)):\(Self.pad(minute)):\(Self.pad(second))"
    }

    /// `YYYY-MM-DD`.
    var dayKey: String {
        "\(monthKey)-\(Self.pad(day))"
    }

    /// `YYYY-MM`, the name of the month file.
    var monthKey: String {
        Self.monthKey(year: year, month: month)
    }

    /// `YYYY-MM` of `year` and `month`.
    static func monthKey(year: Int, month: Int) -> String {
        "\(pad(year, width: 4))-\(pad(month))"
    }

    /// Seconds since local midnight.
    var secondOfDay: Int {
        hour * 3600 + minute * 60 + second
    }

    // MARK: Offsets

    /// Parses `Z`, `±HH:MM`, or `±HHMM` into seconds east of UTC.
    static func parseOffset(_ text: String) -> Int? {
        if text == "Z" || text == "z" {
            return 0
        }
        let digits = text.dropFirst().filter { $0 != ":" }
        guard let sign = text.first, sign == "+" || sign == "-", digits.count == 4,
              let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
              hours <= 18, minutes < 60
        else {
            return nil
        }
        let magnitude = hours * 3600 + minutes * 60
        return sign == "-" ? -magnitude : magnitude
    }

    /// Formats seconds east of UTC as `±HH:MM`.
    static func offsetText(_ seconds: Int) -> String {
        let magnitude = abs(seconds) / 60
        return (seconds < 0 ? "-" : "+") + "\(pad(magnitude / 60)):\(pad(magnitude % 60))"
    }

    /// Parses a local time without an offset (in `timeZone`) or an RFC 3339
    /// time with one.
    static func instant(_ text: String, timeZone: TimeZone) -> Date? {
        if let local = Self(text: text) {
            return local.date(in: timeZone)
        }
        guard text.count > 19, let local = Self(text: text.prefix(19)) else {
            return nil
        }
        var suffix = String(text.dropFirst(19))
        if suffix.first == "." {
            suffix = String(suffix.drop { $0 == "." || $0.isNumber })
        }
        return parseOffset(suffix).map { local.date(utcOffset: $0) }
    }

    // MARK: Calendar arithmetic

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = floorDivide(shiftedYear, by: 400)
        let yearOfEra = shiftedYear - era * 400
        let monthIndex = (month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400)) ? 29 : 28
        case 4, 6, 9, 11:
            30
        default:
            31
        }
    }

    static func floorDivide(_ value: Int, by divisor: Int) -> Int {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    private static func pad(_ value: Int, width: Int = 2) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
