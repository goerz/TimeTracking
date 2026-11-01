// The Calendar's subscriptions while it is visible: the block log and
// EventKit (spec_calendar.md §3.4, §4.1).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// Follows the block log.
    func followActivity() async {
        for await _ in activity.changes {
            await reload()
        }
    }

    /// Follows EventKit (`EKEventStoreChanged`).
    func followEvents() async {
        for await _ in events.changes {
            await reload()
        }
    }
}
