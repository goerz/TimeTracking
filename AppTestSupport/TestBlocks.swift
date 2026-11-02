// TestBlocks: activity blocks for the Calendar tests on the Mac
// and the iPad (spec_calendar.md §3.3).

import Foundation
import TimeTrackingCore

/// Builds activity blocks for an in-memory activity log.
enum TestBlocks {
    /// A block today (2024-03-14) from `start` to `end`, local time, 90 %
    /// active, all of it in `tmux:paper`.
    static func block(_ start: String, _ end: String, open: Bool = false) throws -> ActivityBlock {
        let context = "tmux:paper"
        let begin = try TestDates.date("2024-03-14T\(start)")
        let finish = try TestDates.date("2024-03-14T\(end)")
        let seconds = Int(finish.timeIntervalSince(begin) * 0.9)
        return ActivityBlock(
            start: begin,
            end: finish,
            activeSeconds: seconds,
            devices: [ActivityDeviceTime(name: "macbook", seconds: seconds, isRecordingMac: true)],
            groupKey: context,
            groupShare: 1,
            items: [ActivityItem(context: context, subject: "~/Papers", detail: "", seconds: seconds, device: "macbook")],
            utcOffset: TimeZone.current.secondsFromGMT(for: begin),
            isOpen: open
        )
    }
}
