// TestBlocks: activity blocks for the Calendar tests on the Mac
// and the iPad (calendar.md §3.3).

import Foundation
import TimeTrackingCore

/// Builds activity blocks for an in-memory activity log.
enum TestBlocks {
    /// A block today (2024-03-14) from `start` to `end`, local time, 90 %
    /// active, all of it in WezTerm in the workspace `paper`.
    static func block(_ start: String, _ end: String, open: Bool = false) throws -> ActivityBlock {
        let begin = try TestDates.date("2024-03-14T\(start)")
        let finish = try TestDates.date("2024-03-14T\(end)")
        let seconds = Int(finish.timeIntervalSince(begin) * 0.9)
        let item = ActivityItem(
            app: "WezTerm",
            appID: "com.github.wez.wezterm",
            session: "paper",
            location: "~/Papers",
            workspace: "paper"
        )
        return ActivityBlock(
            start: begin,
            end: finish,
            utcOffset: TimeZone.current.secondsFromGMT(for: begin),
            foreground: [ActivityBlockItem(device: "MacBook", seconds: seconds, item: item)],
            isOpen: open
        )
    }
}
