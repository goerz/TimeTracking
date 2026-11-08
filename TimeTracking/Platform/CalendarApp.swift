// CalendarApp: opens an event in Calendar.app
// (calendar.md §4.3).

import AppKit
import TimeTrackingCore

/// Calendar.app on the Mac.
enum CalendarApp {
    /// Shows the event's day in Calendar.app (EventKit has no deep link to an event).
    static func open(_ event: CalendarEvent) {
        let seconds = Int(event.start.timeIntervalSinceReferenceDate)
        if let url = URL(string: "ical://ekevent/\(seconds)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }
}
