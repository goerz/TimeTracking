// Time: the timestamp encoding of the schema (spec_data_and_sync.md §2.1).
// Timestamps are Unix seconds except `modified_at` (milliseconds).

import Foundation

enum Time {
    static func seconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    static func seconds(optional date: Date?) -> Int64? {
        date.map { seconds($0) }
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func date(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func date(optional seconds: Int64?) -> Date? {
        seconds.map { date($0) }
    }

    static func date(millis: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    /// `date` truncated to whole seconds.
    static func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// `date` truncated to whole milliseconds.
    static func wholeMillis(_ instant: Date) -> Date {
        date(millis: millis(instant))
    }
}
