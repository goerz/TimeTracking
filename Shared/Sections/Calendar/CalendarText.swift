// CalendarText: times of day and ranges in the Calendar's zone
// (calendar.md §1.5, §2.3, §3.2, §4.3).

import Foundation
import TimeTrackingCore

/// Times and ranges in the zone.
enum CalendarText {
    static func clock(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ActivityText.clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// "09:10 – 09:44".
    static func range(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        "\(clock(start, zone: zone)) – \(clock(end, zone: zone))"
    }
}
