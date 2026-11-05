// The views that show sleep and workouts: the Calendar's lines and the
// time Reports count (calendar.md §3.1, reports.md §1.1).

import Foundation

extension AppModel {
    /// After health periods or the Calendar's settings change: the Calendar
    /// settings' import status, Reports, and a visible Calendar re-read.
    func reloadHealthViews() async {
        await sections.calendar.loadHealthImport()
        guard mainWindowIsOpen else {
            return
        }
        await sections.reports.reload()
        if sections.section == .calendar {
            await sections.calendar.reload()
        }
    }
}
