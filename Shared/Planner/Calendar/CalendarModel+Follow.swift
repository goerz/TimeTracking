// The Calendar's subscriptions while it is visible: the block log and
// EventKit (spec_planner_calendar.md §3.4, §4.1, §5.5).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// Follows the block log; a changed month file also updates the
    /// suggestions index (throttled like entry changes).
    func followActivity() async {
        for await change in activity.changes {
            await reload()
            if case .blocks = change {
                await engine.entriesChanged(titles: trainingTitles())
            }
        }
    }

    /// Follows EventKit (`EKEventStoreChanged`).
    func followEvents() async {
        for await _ in events.changes {
            await reload()
        }
    }
}
