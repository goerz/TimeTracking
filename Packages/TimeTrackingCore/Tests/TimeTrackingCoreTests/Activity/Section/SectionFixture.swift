// Helpers for the Activity section's tests (activity.md §1): the week of
// March 11 to 17, 2024 seen on Thursday, the test clock's day, and summaries
// built from blocks.

import Foundation
import TimeTrackingCore

enum SectionFixture {
    /// Monday, March 11, 2024.
    static let monday = TrackingDay(year: 2024, month: 3, day: 11)
    /// Thursday, March 14, 2024, today in these tests.
    static let thursday = TrackingDay(year: 2024, month: 3, day: 14)
    /// This week, Monday to Sunday.
    static let week = monday ... TrackingDay(year: 2024, month: 3, day: 17)

    static let mail = ActivityFixture.app("Mail", appID: "com.apple.mail")
    static let skim = ActivityFixture.app("Skim", appID: "net.sourceforge.skim-app.skim")

    /// A Safari page with its own window title.
    static func page(_ url: String, window: String, workspace: String, appID: String = "com.apple.Safari") -> ActivityItem {
        ActivityItem(app: "Safari", appID: appID, window: window, location: url, workspace: workspace)
    }

    /// The summary of `blocks` over `days` (this week by default) on Thursday.
    static func summary(
        _ blocks: [ActivityBlock],
        background: [ActivityBlock] = [],
        days: ClosedRange<TrackingDay> = week,
        apps: Set<String> = [],
        device: String? = nil,
        settings: TrackerSettings = .defaults,
        exclusions: ExclusionRules? = nil
    ) -> ActivitySummary {
        ActivitySummary(ActivitySummaryInput(
            blocks: blocks,
            backgroundBlocks: background,
            days: days,
            today: thursday,
            apps: apps,
            device: device,
            settings: settings,
            exclusions: exclusions
        ))
    }

    /// The block as the open block of `current.json`.
    static func opened(_ block: ActivityBlock) -> ActivityBlock {
        var result = block
        result.isOpen = true
        result.endReason = nil
        return result
    }

    /// The block with every foreground item on `device`.
    static func moved(_ block: ActivityBlock, to device: String) -> ActivityBlock {
        var result = block
        for index in result.foreground.indices {
            result.foreground[index].device = device
        }
        return result
    }

    /// The days of `days` as an interval in New York time.
    static func interval(_ days: ClosedRange<TrackingDay>) -> DateInterval {
        TrackingCalendar(timeZone: ActivityFixture.newYork).interval(of: days)
    }

    /// A tracker state with `block` open, last ticking at `lastTick`.
    static func trackerState(
        block: ActivityBlock?,
        lastTick: Date,
        sources: [TrackerSourceHealth] = [TrackerSourceHealth(id: "window", name: "Window titles", status: .active)]
    ) -> TrackerState {
        TrackerState(
            block: block,
            foreground: ActivityFixture.terminal(),
            presence: TrackerPresence(state: .active, since: lastTick - 600),
            health: TrackerHealth(lastTick: lastTick, version: "1.0", sources: sources)
        )
    }
}
